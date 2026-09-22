#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Corrects two factually wrong statements that are live on the App Store.
#
# WHY THIS IS A SCRIPT AND NOT A ONE-OFF
#
# Both strings were wrong for the same reason: a number in user-facing copy that
# nobody re-derived from source. Writing the correction down means the next person
# can see which line of `QuotaPolicy.swift` each number came from, rather than
# trusting that whoever typed it checked. Run it, read the HTTP codes, done.
#
# WHAT IT CHANGES
#
# 1. Promotional text on the live 5.3 listings, both platforms.
#    The listing said "Lifetime is 33% off". One promotional-text string is served
#    to every storefront and the real discount is not one number: a check on
#    2026-09-19 measured 32.2% in India, 30.8% in Mexico and 40.0% in Australia.
#    The app itself computes the true percentage for the customer's own storefront
#    from StoreKit prices and shows it in the sale banner, so the listing was
#    contradicting the app. The new line keeps the deadline and drops the figure.
#
#    "Unlimited documents" is deliberately KEPT. `QuotaPolicy.lifetimeDocumentLimit`
#    is `unlimitedDocumentLimit`, which is `Int.max`, and the sentence is about
#    Lifetime. Withdrawing a true claim is its own defect, and this repository has
#    done it before.
#
# 2. Both Pro subscription descriptions.
#    They read "unlimited documents and 5 libraries". `QuotaPolicy.proDocumentLimit`
#    is 1_000 and `QuotaPolicy.proLibraryLimit` is 10, so both halves were wrong,
#    and the library count was wrong in the direction that undersells the plan.
#
# NOTE ON REVIEW. Promotional text is editable on a live version without a new
# submission. Subscription localizations may enter review; if a PATCH returns 409
# with ENTITY_ERROR ... UNMODIFIABLE, the description is frozen and needs a new
# subscription version, which is the same wall the Pro Annual rename hit on
# 2026-09-18. The script reports the code rather than guessing.
#
# Usage:
#   zsh -ic 'ruby scripts/asc_fix_listing_copy.rb'          # apply
#   zsh -ic 'ruby scripts/asc_fix_listing_copy.rb --dry-run' # show, change nothing
#
# Reads APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID and _API_KEY_PATH from the
# environment, which `~/.zshrc` exports, hence `zsh -ic`. Prints no key material.
# This shell's ruby is 2.6, so no endless method definitions and no shorthand hash.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'

DRY_RUN = ARGV.include?('--dry-run')

KEY_ID   = ENV.fetch('APP_STORE_CONNECT_API_KEY_ID')
ISSUER   = ENV.fetch('APP_STORE_CONNECT_ISSUER_ID')
KEY_PATH = ENV.fetch('APP_STORE_CONNECT_API_KEY_PATH')

def b64url(str)
  Base64.urlsafe_encode64(str).delete('=')
end

def make_token
  header  = { 'alg' => 'ES256', 'kid' => KEY_ID, 'typ' => 'JWT' }
  payload = { 'iss' => ISSUER, 'exp' => Time.now.to_i + 900, 'aud' => 'appstoreconnect-v1' }
  signing = b64url(header.to_json) + '.' + b64url(payload.to_json)
  key = OpenSSL::PKey::EC.new(File.read(KEY_PATH))
  der = key.sign(OpenSSL::Digest.new('SHA256'), signing)
  parts = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
  signing + '.' + b64url(parts[0] + parts[1])
end

$token = make_token

def call(verb, path, payload = nil)
  uri = URI('https://api.appstoreconnect.apple.com' + path)
  request = verb == :patch ? Net::HTTP::Patch.new(uri) : Net::HTTP::Get.new(uri)
  request['Authorization'] = 'Bearer ' + $token
  if payload
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json
  end
  response = Net::HTTP.start(uri.host, uri.port, :use_ssl => true) { |h| h.request(request) }
  body = begin
    JSON.parse(response.body)
  rescue StandardError
    { 'raw' => response.body.to_s[0, 400] }
  end
  [response.code.to_i, body]
end

def explain(code, body)
  return nil if code >= 200 && code < 300
  errors = body['errors'] || []
  return body.to_json[0, 400] if errors.empty?
  errors.map { |e| "#{e['code']}: #{e['detail']}" }.join(' | ')
end

# --- 1. promotional text on the live 5.3 listings ---------------------------
#
# Localization ids, not version ids. An earlier audit confused the two, and a
# PATCH to a version id fails in a way that looks like the field is unwritable.
# Re-derive with:
#   GET /v1/appStoreVersions/{vid}/appStoreVersionLocalizations
PROMO_TEXT = 'Lifetime is on sale until September 29: one payment, no renewal, ' \
             'no daily cap on Maximum mode, unlimited documents. Every plan runs ' \
             'the same on-device model.'

PROMO_TARGETS = [
  ['iOS 5.3, live',   '44444bb1-5c2e-4569-834b-109195137ad6'],
  ['macOS 5.3, live', '7dcb9118-d6c9-4477-be60-b9698142b90c']
].freeze

# --- 2. the two Pro subscription descriptions -------------------------------
SUBSCRIPTION_TARGETS = [
  ['Pro Annual',  '49d09ca0-720a-4822-9af0-a08bf0ec7084',
   'Annual billing for up to 1,000 documents and 10 libraries.'],
  ['Pro Monthly', 'bc30168b-6fbf-44dc-af6a-96c26bf6b8b7',
   'Monthly billing for up to 1,000 documents and 10 libraries.']
].freeze

failures = 0

puts
puts 'Promotional text'
puts '-' * 74
puts "  #{PROMO_TEXT.length} of 170 characters"
abort('  promotional text is over Apple\'s 170 character limit') if PROMO_TEXT.length > 170

PROMO_TARGETS.each do |label, loc_id|
  before_code, before = call(:get, "/v1/appStoreVersionLocalizations/#{loc_id}")
  current = before_code == 200 ? before['data']['attributes']['promotionalText'].to_s : '(unreadable)'
  puts
  puts "  #{label}"
  puts "    before: #{current[0, 120].inspect}"

  if DRY_RUN
    puts "    after : #{PROMO_TEXT[0, 120].inspect}  (dry run, nothing sent)"
    next
  end

  payload = { 'data' => { 'type' => 'appStoreVersionLocalizations', 'id' => loc_id,
                          'attributes' => { 'promotionalText' => PROMO_TEXT } } }
  code, body = call(:patch, "/v1/appStoreVersionLocalizations/#{loc_id}", payload)
  problem = explain(code, body)
  if problem
    failures += 1
    puts "    HTTP #{code}  #{problem}"
  else
    puts "    after : #{body['data']['attributes']['promotionalText'][0, 120].inspect}  (HTTP #{code})"
  end
end

puts
puts 'Pro subscription descriptions'
puts '-' * 74
SUBSCRIPTION_TARGETS.each do |label, loc_id, description|
  before_code, before = call(:get, "/v1/subscriptionLocalizations/#{loc_id}")
  current = before_code == 200 ? before['data']['attributes']['description'].to_s : '(unreadable)'
  puts
  puts "  #{label}"
  puts "    before: #{current.inspect}"

  if DRY_RUN
    puts "    after : #{description.inspect}  (dry run, nothing sent)"
    next
  end

  payload = { 'data' => { 'type' => 'subscriptionLocalizations', 'id' => loc_id,
                          'attributes' => { 'description' => description } } }
  code, body = call(:patch, "/v1/subscriptionLocalizations/#{loc_id}", payload)
  problem = explain(code, body)
  if problem
    failures += 1
    puts "    HTTP #{code}  #{problem}"
    puts '    A 409 UNMODIFIABLE here means the description is frozen on an approved' if code == 409
    puts '    subscription and needs a new subscription version to change.' if code == 409
  else
    puts "    after : #{body['data']['attributes']['description'].inspect}  (HTTP #{code})"
  end
end

puts
if DRY_RUN
  puts 'Dry run. Nothing was sent.'
elsif failures.zero?
  puts 'All four statements corrected.'
else
  puts "#{failures} of 4 failed. Read the HTTP codes above before retrying."
  exit 1
end
