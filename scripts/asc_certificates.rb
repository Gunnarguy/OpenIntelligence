#!/usr/bin/env ruby
# frozen_string_literal: true
#
# List and revoke Apple development certificates, for CI cleanup.
#
# Why this exists: automatic signing provisions a development certificate on every
# fresh runner. The archive phase signs for development and `-exportArchive` re-signs
# for distribution afterwards, which is correct behaviour and cannot be pinned away —
# forcing `CODE_SIGN_IDENTITY=Apple Distribution` on the archive fails with
# "conflicting provisioning settings" (tried, run 385).
#
# The certificates accumulate. Ten built up across runs 378 to 383 on 2026-08-26 and
# run 384 failed outright: "Choose a certificate to revoke. Your account has reached
# the maximum number of certificates." Left alone that recurs roughly every ten
# builds.
#
# `revoke-new` compares against a snapshot taken before the archive, so it revokes
# only what the current run created and can never touch one that already existed.
# That distinction is the whole safety property: revoking a certificate is
# irreversible, and the pre-existing one is the owner's.
#
# Known limit: two runs in parallel each see the other's certificate as new, so both
# refuse rather than guess, and neither cleans up. Build the platforms sequentially
# and it self-cleans; build them together and prune by hand occasionally. Refusing is
# the correct failure here — revoking the wrong certificate cannot be undone.
#
# Reads APP_STORE_CONNECT_* or ASC_* from the environment. Never prints key material.
#
# Usage:
#   ruby scripts/asc_certificates.rb list
#   ruby scripts/asc_certificates.rb revoke-new <path-to-snapshot>

require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'set'

def env(*names)
  names.each { |n| v = ENV[n]; return v if v && !v.empty? }
  abort("Missing any of: #{names.join(', ')}")
end

KEY_ID    = env('APP_STORE_CONNECT_API_KEY_ID', 'ASC_KEY_ID')
ISSUER_ID = env('APP_STORE_CONNECT_ISSUER_ID', 'ASC_ISSUER_ID')

KEY_PATH = [
  ENV['APP_STORE_CONNECT_API_KEY_PATH'],
  File.join(Dir.home, '.appstoreconnect', 'private_keys', "AuthKey_#{KEY_ID}.p8")
].compact.find { |p| !p.empty? && File.exist?(p) }
abort('No App Store Connect key file found') unless KEY_PATH

def b64url(str) = Base64.urlsafe_encode64(str).delete('=')

def token
  ec = OpenSSL::PKey::EC.new(File.read(KEY_PATH))
  now = Time.now.to_i
  header  = b64url({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' }.to_json)
  payload = b64url({ iss: ISSUER_ID, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }.to_json)
  signing_input = "#{header}.#{payload}"
  asn1 = OpenSSL::ASN1.decode(ec.sign(OpenSSL::Digest::SHA256.new, signing_input))
  r = asn1.value[0].value.to_s(2).rjust(32, "\x00".b)
  s = asn1.value[1].value.to_s(2).rjust(32, "\x00".b)
  "#{signing_input}.#{b64url(r + s)}"
end

BEARER = token

def request(verb, path)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  klass = verb == 'DELETE' ? Net::HTTP::Delete : Net::HTTP::Get
  req = klass.new(uri)
  req['Authorization'] = "Bearer #{BEARER}"
  Net::HTTP.start(uri.host, 443, use_ssl: true, open_timeout: 15, read_timeout: 30) { |h| h.request(req) }
end

def development_certificate_ids
  res = request('GET', '/v1/certificates?limit=200')
  abort("Could not list certificates: HTTP #{res.code}") unless res.code == '200'
  JSON.parse(res.body).fetch('data', [])
      .select { |c| c.dig('attributes', 'certificateType') == 'DEVELOPMENT' }
      .map { |c| c['id'] }
end

case ARGV[0]
when 'list'
  puts development_certificate_ids
when 'revoke-new'
  snapshot_path = ARGV[1] or abort('revoke-new needs a snapshot path')
  before = File.readlines(snapshot_path).map(&:strip).reject(&:empty?).to_set
  created = development_certificate_ids.reject { |id| before.include?(id) }

  if created.empty?
    puts 'No development certificate was created by this run; nothing to revoke.'
    exit 0
  end

  # A run creates at most one. More than that means the snapshot is not describing
  # this run — a concurrent build, or a stale file — and guessing which to destroy is
  # exactly the move that makes an irreversible action dangerous.
  if created.length > 1
    warn("Expected at most one new certificate, found #{created.length}: #{created.join(', ')}.")
    warn('Refusing to revoke. Prune by hand rather than guessing.')
    exit 1
  end

  id = created.first
  res = request('DELETE', "/v1/certificates/#{id}")
  if %w[200 204].include?(res.code)
    puts "Revoked development certificate #{id}, created by this run."
  else
    warn("Could not revoke #{id}: HTTP #{res.code}")
    exit 1
  end
else
  abort('Usage: asc_certificates.rb list | revoke-new <snapshot>')
end
