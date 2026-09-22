#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Gets an App Store version ready to submit, on both platforms, without submitting it:
#   1. attaches the given build number to the iOS and macOS version records
#   2. writes What's New, description and keywords from fastlane/metadata/en-US/
#
# It never submits for review. That stays the owner's button in App Store Connect.
#
# Usage:
#   zsh -ic 'ruby scripts/asc_prepare_release.rb 5.4 469'            # dry run
#   zsh -ic 'ruby scripts/asc_prepare_release.rb 5.4 469 --apply'
#
# Files are read as UTF-8 explicitly: a non-interactive shell defaults to US-ASCII and the '•'
# bullets in the release notes then fail JSON encoding (2026-09-22).
# Reads APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID and _API_KEY_PATH, exported by ~/.zshrc, hence
# `zsh -ic`. Prints no key material. Ruby 2.6 compatible.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'

APP_ID = '6756559175'
VERSION, BUILD = ARGV.reject { |a| a.start_with?('--') }
abort('usage: asc_prepare_release.rb <version> <build> [--apply]') unless VERSION && BUILD
APPLY = ARGV.include?('--apply')
META = File.expand_path('../fastlane/metadata/en-US', __dir__)
TEXT = {
  'whatsNew' => File.read(File.join(META, 'release_notes.txt'), encoding: 'UTF-8').strip,
  'description' => File.read(File.join(META, 'description.txt'), encoding: 'UTF-8').strip,
  'keywords' => File.read(File.join(META, 'keywords.txt'), encoding: 'UTF-8').strip
}.freeze
{ 'whatsNew' => 4000, 'description' => 4000, 'keywords' => 100 }.each do |k, max|
  abort("#{k} is #{TEXT[k].length} characters, limit #{max}") if TEXT[k].length > max
end

KEY_ID   = ENV.fetch('APP_STORE_CONNECT_API_KEY_ID')
ISSUER   = ENV.fetch('APP_STORE_CONNECT_ISSUER_ID')
KEY_PATH = ENV.fetch('APP_STORE_CONNECT_API_KEY_PATH')

def b64url(str)
  Base64.urlsafe_encode64(str).delete('=')
end

def token
  header  = { 'alg' => 'ES256', 'kid' => KEY_ID, 'typ' => 'JWT' }
  payload = { 'iss' => ISSUER, 'exp' => Time.now.to_i + 900, 'aud' => 'appstoreconnect-v1' }
  signing = b64url(header.to_json) + '.' + b64url(payload.to_json)
  key = OpenSSL::PKey::EC.new(File.read(KEY_PATH))
  der = key.sign(OpenSSL::Digest.new('SHA256'), signing)
  parts = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
  signing + '.' + b64url(parts[0] + parts[1])
end

def call(verb, path, body = nil)
  uri = URI('https://api.appstoreconnect.apple.com' + path)
  request = { get: Net::HTTP::Get, patch: Net::HTTP::Patch }.fetch(verb).new(uri)
  request['Authorization'] = 'Bearer ' + token
  if body
    request['Content-Type'] = 'application/json'
    request.body = body.to_json
  end
  response = Net::HTTP.start(uri.host, uri.port, :use_ssl => true) { |h| h.request(request) }
  parsed = begin
    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  rescue StandardError
    { 'raw' => response.body.to_s[0, 300] }
  end
  [response.code.to_i, parsed]
end

def problem(code, body)
  return nil if code.between?(200, 299)
  errs = (body['errors'] || []).map { |e| "#{e['code']}: #{e['detail']}" }
  "HTTP #{code} #{errs.empty? ? body.to_json[0, 300] : errs.join(' | ')}"
end

# Builds with this number, keyed by platform.
code, builds = call(:get, "/v1/builds?filter[app]=#{APP_ID}&filter[version]=#{BUILD}&include=preReleaseVersion&limit=10")
abort("builds lookup #{problem(code, builds)}") unless code == 200
platform_of = (builds['included'] || []).each_with_object({}) { |p, h| h[p['id']] = p['attributes']['platform'] }
build_for = {}
(builds['data'] || []).each do |b|
  pid = b.dig('relationships', 'preReleaseVersion', 'data', 'id')
  build_for[platform_of[pid]] = [b['id'], b['attributes']['processingState']] if pid
end

failures = 0
%w[IOS MAC_OS].each do |platform|
  code, versions = call(:get, "/v1/apps/#{APP_ID}/appStoreVersions?filter[platform]=#{platform}&filter[versionString]=#{VERSION}&limit=1")
  version = (versions['data'] || []).first
  unless version
    puts "#{platform}: no #{VERSION} version record"
    failures += 1
    next
  end
  state = version['attributes']['appStoreState']
  puts "#{platform} #{VERSION} (#{state})"
  build_id, processing = build_for[platform]
  if build_id.nil?
    puts "  build #{BUILD} not found for this platform"
    failures += 1
  elsif processing != 'VALID'
    puts "  build #{BUILD} is #{processing}, not VALID yet"
    failures += 1
  elsif APPLY
    code, body = call(:patch, "/v1/appStoreVersions/#{version['id']}/relationships/build",
                      { 'data' => { 'type' => 'builds', 'id' => build_id } })
    msg = problem(code, body)
    failures += 1 if msg
    puts "  build #{BUILD}: #{msg || 'attached'}"
  else
    puts "  build #{BUILD}: would attach (dry run)"
  end

  code, locs = call(:get, "/v1/appStoreVersions/#{version['id']}/appStoreVersionLocalizations?limit=10")
  loc = (locs['data'] || []).find { |l| l['attributes']['locale'] == 'en-US' }
  unless loc
    puts '  no en-US localization'
    failures += 1
    next
  end
  if APPLY
    code, body = call(:patch, "/v1/appStoreVersionLocalizations/#{loc['id']}",
                      { 'data' => { 'type' => 'appStoreVersionLocalizations', 'id' => loc['id'], 'attributes' => TEXT } })
    msg = problem(code, body)
    failures += 1 if msg
    puts "  what's new, description, keywords: #{msg || 'written'}"
  else
    puts "  what's new (#{TEXT['whatsNew'].length}), description (#{TEXT['description'].length}), keywords: would write (dry run)"
  end
end

puts
puts APPLY ? (failures.zero? ? "Ready to submit #{VERSION} in App Store Connect. Nothing was submitted." : "#{failures} problem(s) above.") : 'Dry run. Add --apply to write.'
exit(failures.zero? ? 0 : 1)
