#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Lists the Xcode versions Xcode Cloud offers and repoints the Default workflow at one.
#
# Why this exists: every Private Cloud Compute path sits behind `#if compiler(>=6.4)`, so the
# toolchain decides whether PCC ships. The workflow is pinned to an Xcode version by id, not
# to "Latest Release", and the pin lives in App Store Connect where nothing in the repo can
# see it. This script is the repo's eyes and hands on that setting. Verified 2026-09-02: the
# API accepts the PATCH even though the workflow reports isLockedForEditing=true.
#
# Usage:
#   ruby scripts/xcode_cloud_toolchain.rb                  # list, and show the current pin
#   ruby scripts/xcode_cloud_toolchain.rb --set 'Xcode 27'   # repoint by (prefix of) name or by id
#
# Reads APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID and _API_KEY_PATH from the environment, the
# same three scripts/asc_healthcheck.rb uses (exported from ~/.zshrc).

require 'openssl'
require 'base64'
require 'json'
require 'net/http'

PRODUCT  = 'c6efe188-583b-47d8-9db8-dc8e17ecc7c5' # OpenIntelligence ciProduct
WORKFLOW = 'E6B22BA8-D5A5-4664-941A-3EC1C3F50910' # "Default"

kid = ENV['APP_STORE_CONNECT_API_KEY_ID']
iss = ENV['APP_STORE_CONNECT_ISSUER_ID']
path = ENV['APP_STORE_CONNECT_API_KEY_PATH']
abort 'APP_STORE_CONNECT_API_KEY_ID / _ISSUER_ID / _API_KEY_PATH are not all set' unless kid && iss && path

key = OpenSSL::PKey::EC.new(File.read(File.expand_path(path)))
enc = ->(h) { Base64.urlsafe_encode64(JSON.generate(h), padding: false) }
now = Time.now.to_i
signing_input = "#{enc.call({ alg: 'ES256', kid: kid, typ: 'JWT' })}.#{enc.call({ iss: iss, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' })}"
der = key.sign(OpenSSL::Digest::SHA256.new, signing_input)
r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
TOKEN = "#{signing_input}.#{Base64.urlsafe_encode64(r + s, padding: false)}"

def api(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com/v1/#{path}")
  req = (method == :patch ? Net::HTTP::Patch : Net::HTTP::Get).new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body) if body
  res = Net::HTTP.start(uri.host, 443, use_ssl: true) { |h| h.request(req) }
  [res.code.to_i, res.body.to_s.empty? ? {} : JSON.parse(res.body)]
end

_, versions = api(:get, 'ciXcodeVersions?limit=50')
available = versions['data'].map { |x| { id: x['id'], name: x['attributes']['name'], version: x['attributes']['version'] } }
_, wf = api(:get, "ciWorkflows/#{WORKFLOW}?include=xcodeVersion")
current = (wf['included'] || []).find { |i| i['type'] == 'ciXcodeVersions' }

puts "Workflow 'Default' currently builds with: #{current ? "#{current['attributes']['name']} (#{current['attributes']['version']})" : 'unknown'}"
puts 'Available on Xcode Cloud:'
available.each { |v| puts "  #{v[:name].ljust(24)} #{v[:version].ljust(10)} #{v[:id]}" }

if ARGV[0] == '--set'
  want = ARGV[1] or abort "--set needs a name prefix or id, e.g. --set 'Xcode 27'"
  match = available.find { |v| v[:id] == want } || available.find { |v| v[:name].start_with?(want) }
  abort "No Xcode Cloud version matches #{want.inspect}. Apple has not published it yet, or the name differs." unless match
  if match[:name] =~ /beta/i
    warn "WARNING: #{match[:name]} is a beta. Builds from it can go to TestFlight but cannot be submitted to the App Store."
  end
  code, res = api(:patch, "ciWorkflows/#{WORKFLOW}", { data: { type: 'ciWorkflows', id: WORKFLOW, relationships: { xcodeVersion: { data: { type: 'ciXcodeVersions', id: match[:id] } } } } })
  abort "PATCH failed: HTTP #{code} #{res.dig('errors', 0, 'detail')}" unless code == 200
  _, wf2 = api(:get, "ciWorkflows/#{WORKFLOW}?include=xcodeVersion")
  after = (wf2['included'] || []).find { |i| i['type'] == 'ciXcodeVersions' }
  puts "Repointed. Workflow now builds with: #{after['attributes']['name']} (#{after['attributes']['version']})"
  puts 'The next push to main builds with it. To build without pushing, start the workflow from App Store Connect.'
end
