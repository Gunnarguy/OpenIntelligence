#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Creates the one retention message shown when a Pro subscriber goes to cancel, and makes it the
# default for both Pro subscriptions. No server, no image, no App Store Connect screens.
#
# PREREQUISITE, ONCE
#
# Apple gates the Retention Messaging API behind an access request. Until it is granted, every
# messaging route on api.storekit.apple.com returns an empty 404 with a valid token (measured
# 2026-09-22: a known Server API route on the same host returned 200 with the same token, and a
# bad token got 401 on the messaging route, so the 404 is entitlement, not auth or path). The
# request form is https://developer.apple.com/contact/request/retention-messaging-api/ and needs
# the owner's Apple ID. This script tells you plainly if access is still missing.
#
# WHAT IT DOES
#
#   1. PUT  /inApps/v1/messaging/message/{uuid}          the message: header (66 max), body (144 max)
#   2. GET  /inApps/v1/messaging/message/list            waits for Apple to mark it APPROVED
#   3. PUT  /inApps/v1/messaging/default/{productId}/en-US   for pro_monthly and pro_annual
#
# A default message is text only; the App Store attaches the customer's best eligible win-back
# offer itself. Apple reviews the message; in production it starts PENDING and step 3 is refused
# until it is APPROVED, so a run before approval ends after step 2 and says so. Run it again later.
# Idempotent: the message identifier is fixed, and re-uploading returns 409 which is treated as
# "already there".
#
# Usage:
#   zsh -ic 'ruby scripts/asc_retention_message.rb'            # production
#   zsh -ic 'ruby scripts/asc_retention_message.rb --sandbox'  # sandbox, approved instantly
#
# Reads APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID and _API_KEY_PATH from the environment, which
# ~/.zshrc exports, hence `zsh -ic`. Prints no key material. Ruby 2.6 compatible.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'

SANDBOX = ARGV.include?('--sandbox')
HOST = SANDBOX ? 'api.storekit-sandbox.apple.com' : 'api.storekit.apple.com'
BUNDLE_ID = 'Gunndamental.OpenIntelligence'
PRODUCT_IDS = %w[pro_monthly pro_annual].freeze
LOCALE = 'en-US'

# Fixed so a second run finds the same message instead of making another.
MESSAGE_ID = 'a3f1c2d4-5e6b-4a7c-9d8e-0f1a2b3c4d5e'
HEADER = 'Your libraries and every answer stay on this device'
BODY = 'Cancelling keeps your documents. It ends the Maximum cap lift and the 1,000-document ' \
       'limit. A win-back offer is available if you come back later.'
abort("header is #{HEADER.length} characters, limit 66") if HEADER.length > 66
abort("body is #{BODY.length} characters, limit 144") if BODY.length > 144

KEY_ID   = ENV.fetch('APP_STORE_CONNECT_API_KEY_ID')
ISSUER   = ENV.fetch('APP_STORE_CONNECT_ISSUER_ID')
KEY_PATH = ENV.fetch('APP_STORE_CONNECT_API_KEY_PATH')

def b64url(str)
  Base64.urlsafe_encode64(str).delete('=')
end

# The App Store Server API token shape: same key, plus the bid claim, at most 60 minutes.
def token
  now = Time.now.to_i
  header  = { 'alg' => 'ES256', 'kid' => KEY_ID, 'typ' => 'JWT' }
  payload = { 'iss' => ISSUER, 'iat' => now, 'exp' => now + 1800, 'aud' => 'appstoreconnect-v1', 'bid' => BUNDLE_ID }
  signing = b64url(header.to_json) + '.' + b64url(payload.to_json)
  key = OpenSSL::PKey::EC.new(File.read(KEY_PATH))
  der = key.sign(OpenSSL::Digest.new('SHA256'), signing)
  parts = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
  signing + '.' + b64url(parts[0] + parts[1])
end

def call(verb, path, body = nil)
  uri = URI("https://#{HOST}#{path}")
  request = verb == :put ? Net::HTTP::Put.new(uri) : Net::HTTP::Get.new(uri)
  request['Authorization'] = 'Bearer ' + token
  if body
    request['Content-Type'] = 'application/json'
    request.body = body.to_json
  end
  response = Net::HTTP.start(uri.host, uri.port, :use_ssl => true) { |h| h.request(request) }
  parsed = begin
    JSON.parse(response.body)
  rescue StandardError
    { 'raw' => response.body.to_s[0, 300] }
  end
  [response.code.to_i, parsed]
end

puts "host: #{HOST}"

# --- 0. entitlement check, read only ---------------------------------------
code, list = call(:get, '/inApps/v1/messaging/message/list')
if code == 404 && (list['raw'].to_s.strip.empty?)
  puts 'Retention Messaging is not enabled for this account yet (empty 404 on the message list).'
  puts 'Submit https://developer.apple.com/contact/request/retention-messaging-api/ signed in as the'
  puts 'Account Holder, then run this again. Nothing else to do here until then.'
  exit 2
end
abort("message list HTTP #{code}: #{list.to_json[0, 300]}") unless code == 200

# --- 1. the message ----------------------------------------------------------
code, resp = call(:put, "/inApps/v1/messaging/message/#{MESSAGE_ID}", { 'header' => HEADER, 'body' => BODY, 'headerPosition' => 'ABOVE_BODY' })
case code
when 200 then puts "message uploaded (#{MESSAGE_ID})"
when 409 then puts 'message already uploaded'
else abort("upload HTTP #{code}: #{resp.to_json[0, 300]}")
end

# --- 2. its state -------------------------------------------------------------
code, list = call(:get, '/inApps/v1/messaging/message/list')
abort("message list HTTP #{code}") unless code == 200
item = (list['messages'] || list['messageList'] || list.values.flatten.select { |x| x.is_a?(Hash) }).find { |m| m['messageIdentifier'] == MESSAGE_ID }
state = item ? (item['messageState'] || item['state']) : 'UNKNOWN'
puts "message state: #{state}"
unless state == 'APPROVED'
  puts 'Apple has not approved the message yet. Run this again later; step 3 needs APPROVED.'
  exit 0
end

# --- 3. default for both Pro subscriptions ----------------------------------
failures = 0
PRODUCT_IDS.each do |pid|
  code, resp = call(:put, "/inApps/v1/messaging/default/#{pid}/#{LOCALE}", { 'messageIdentifier' => MESSAGE_ID })
  if code == 200
    puts "default set for #{pid} (#{LOCALE})"
  else
    failures += 1
    puts "default for #{pid}: HTTP #{code} #{resp.to_json[0, 200]}"
  end
end
puts failures.zero? ? 'Done. The message shows in the cancel flow for both Pro subscriptions.' : "#{failures} failed."
exit(failures.zero? ? 0 : 1)
