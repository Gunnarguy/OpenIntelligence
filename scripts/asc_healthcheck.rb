#!/usr/bin/env ruby
# frozen_string_literal: true
#
# App Store Connect credential health check.
#
# Answers one question in about two seconds: can this machine talk to App Store
# Connect right now? Prints configuration and a live auth result. Never prints
# key material, the issuer UUID, or the signed token.
#
# Why this exists: on 2026-08-24 the metadata push had been failing for days.
# Two separate agent sessions diagnosed it from the error text alone and both
# were wrong. The error was a bare 401, which Apple returns identically for a
# revoked key, a wrong issuer, a malformed token and a key that was never an
# App Store Connect key at all. The actual cause was that
# APP_STORE_CONNECT_API_KEY_PATH pointed at ApiKey_5UNPFIPXPPRC.p8, a 12-character
# ID that Apple does not issue for this API, while a working key sat unused in
# ~/Downloads. A reproducible check beats a plausible theory.
#
# Usage:
#   ruby scripts/asc_healthcheck.rb
#   ruby scripts/asc_healthcheck.rb --apps      # also list every visible app
#
# Reads APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID and _API_KEY_PATH from the
# environment. Those are exported from ~/.zshrc. Note that .env.appstore uses
# different variable names (ASC_*) and is NOT what fastlane reads.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'

GREEN = "\e[32m"
RED   = "\e[31m"
YELL  = "\e[33m"
DIM   = "\e[2m"
OFF   = "\e[0m"

def ok(msg)   = puts("  #{GREEN}✓#{OFF} #{msg}")
def bad(msg)  = puts("  #{RED}✗#{OFF} #{msg}")
def warn(msg) = puts("  #{YELL}!#{OFF} #{msg}")
def note(msg) = puts("    #{DIM}#{msg}#{OFF}")

def b64url(str) = Base64.urlsafe_encode64(str).delete('=')

key_id    = ENV['APP_STORE_CONNECT_API_KEY_ID']
issuer_id = ENV['APP_STORE_CONNECT_ISSUER_ID']
key_path  = ENV['APP_STORE_CONNECT_API_KEY_PATH']

puts
puts "App Store Connect credential check"
puts

failed = false

# --- configuration ---------------------------------------------------------
if key_id.to_s.empty?
  bad 'APP_STORE_CONNECT_API_KEY_ID is unset'
  failed = true
elsif key_id.length != 10
  bad "APP_STORE_CONNECT_API_KEY_ID is #{key_id.length} characters (#{key_id})"
  note 'Apple issues 10-character key IDs. A different length means this is not'
  note 'an App Store Connect API key. Check Users and Access > Integrations.'
  failed = true
else
  ok "key id #{key_id}"
end

if issuer_id.to_s.empty?
  bad 'APP_STORE_CONNECT_ISSUER_ID is unset'
  failed = true
elsif issuer_id !~ /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  bad 'APP_STORE_CONNECT_ISSUER_ID is not a UUID'
  failed = true
else
  ok 'issuer id present and well formed'
end

if key_path.to_s.empty?
  bad 'APP_STORE_CONNECT_API_KEY_PATH is unset'
  failed = true
elsif !File.exist?(key_path)
  bad "key file missing: #{key_path}"
  failed = true
else
  basename = File.basename(key_path)
  ok "key file #{basename}"
  expected = "AuthKey_#{key_id}.p8"
  if key_id && basename != expected
    warn "filename is not #{expected}"
    note 'Apple names downloaded keys AuthKey_<KEYID>.p8. A different name usually'
    note 'means the wrong file was copied into place.'
  end
  unless File.dirname(key_path).end_with?('.appstoreconnect/private_keys')
    warn 'key is outside ~/.appstoreconnect/private_keys'
    note "notarytool, altool and Transporter auto-discover keys there."
  end
  mode = format('%o', File.stat(key_path).mode)[-3..]
  warn "key file mode is #{mode}, expected 600" unless mode == '600'
end

if failed
  puts
  puts "#{RED}Configuration is incomplete. Not attempting authentication.#{OFF}"
  puts
  exit 1
end

# --- live authentication ---------------------------------------------------
puts
begin
  ec = OpenSSL::PKey::EC.new(File.read(key_path))
rescue StandardError => e
  bad "key will not parse: #{e.class}"
  exit 1
end
ok "key parses, curve #{ec.group.curve_name}"

now = Time.now.to_i
header  = b64url({ alg: 'ES256', kid: key_id, typ: 'JWT' }.to_json)
payload = b64url({ iss: issuer_id, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }.to_json)
signing_input = "#{header}.#{payload}"

der = ec.sign(OpenSSL::Digest::SHA256.new, signing_input)
asn1 = OpenSSL::ASN1.decode(der)
r = asn1.value[0].value.to_s(2).rjust(32, "\x00".b)
s = asn1.value[1].value.to_s(2).rjust(32, "\x00".b)
token = "#{signing_input}.#{b64url(r + s)}"

uri = URI('https://api.appstoreconnect.apple.com/v1/apps?limit=200')
response = Net::HTTP.start(uri.host, 443, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
  http.request(Net::HTTP::Get.new(uri, 'Authorization' => "Bearer #{token}"))
end

if response.code == '200'
  apps = JSON.parse(response.body)['data'] || []
  ok "authenticated, #{apps.length} app(s) visible"
  target = apps.find { |a| a.dig('attributes', 'bundleId') == 'Gunndamental.OpenIntelligence' }
  if target
    ok "OpenIntelligence reachable (id #{target['id']})"
  else
    bad 'OpenIntelligence is NOT visible to this key'
    note 'The key authenticates but against the wrong team, or lacks access to this app.'
    failed = true
  end
  if ARGV.include?('--apps')
    puts
    apps.sort_by { |a| a.dig('attributes', 'bundleId').to_s }.each do |a|
      puts "    #{a.dig('attributes', 'bundleId')}"
    end
  end
else
  bad "HTTP #{response.code}"
  begin
    JSON.parse(response.body)['errors']&.each { |e| note "#{e['code']}: #{e['detail']}" }
  rescue StandardError
    note '(unparseable response body)'
  end
  note 'Apple returns an identical 401 for a revoked key, a wrong issuer and a'
  note 'malformed token. Confirm the key is listed and Active under'
  note 'App Store Connect > Users and Access > Integrations > App Store Connect API.'
  failed = true
end

puts
puts(failed ? "#{RED}NOT READY#{OFF}" : "#{GREEN}READY#{OFF} — fastlane push_metadata will authenticate")
puts
exit(failed ? 1 : 0)
