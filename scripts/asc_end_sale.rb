#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Takes the Lifetime sale off the App Store listing once the sale is over.
#
# WHY THIS IS A SCRIPT
#
# The launch sale is a scheduled App Store price change whose last day is 2026-09-29. The price
# reverts by itself. The promotional text does not: it is plain copy, it says "Lifetime is on sale
# until September 29", and on 2026-09-30 that sentence becomes a false claim on the live listing.
# Nothing in App Store Connect expires it. This script is what does, and it is written so it is
# safe to run at any time, by a person or by a scheduled task:
#
#   - Before 2026-09-30 it refuses to change anything, so running it early cannot end a live sale.
#   - It finds whichever version is actually live on each platform rather than assuming 5.3, because
#     5.4 may have shipped by the time it runs.
#   - It only replaces promotional text that still mentions the sale, so a second run, or a run
#     after someone already fixed it by hand, changes nothing.
#
# The replacement is the non-sale text recorded for 5.3 in
# Docs/Release/APP_STORE_METADATA_HISTORY.md, which is also the text already on the 5.4 records.
#
# Usage:
#   zsh -ic 'ruby scripts/asc_end_sale.rb --dry-run'   # show what would change
#   zsh -ic 'ruby scripts/asc_end_sale.rb'             # apply, from 2026-09-30 on
#
# Reads APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID and _API_KEY_PATH from the environment, which
# ~/.zshrc exports, hence `zsh -ic`. Prints no key material. Ruby 2.6 compatible.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'date'

DRY_RUN = ARGV.include?('--dry-run')
SALE_LAST_DAY = Date.new(2026, 9, 29)
APP_ID = '6756559175' # Gunndamental.OpenIntelligence; one app record serves iOS and macOS

NON_SALE_TEXT = "The sample library's questions are back, the welcome screens follow light and " \
                'dark, and a new off-by-default setting adapts each answer to the question you asked.'

# What a sale line looks like. Broad on purpose: a missed sale line is a false claim, and a
# false positive here only rewrites copy to the text 5.4 already carries.
SALE_PATTERN = /\bon sale\b|%\s*off\b|\boff until\b|\blaunch (price|sale|discount)\b/i

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

def call(verb, path, payload = nil)
  uri = URI('https://api.appstoreconnect.apple.com' + path)
  request = verb == :patch ? Net::HTTP::Patch.new(uri) : Net::HTTP::Get.new(uri)
  request['Authorization'] = 'Bearer ' + token
  if payload
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json
  end
  response = Net::HTTP.start(uri.host, uri.port, :use_ssl => true) { |h| h.request(request) }
  body = begin
    JSON.parse(response.body)
  rescue StandardError
    {}
  end
  [response.code.to_i, body]
end

today = Date.today
if today <= SALE_LAST_DAY && !DRY_RUN
  puts "Today is #{today}. The sale runs through #{SALE_LAST_DAY}, so the listing is left alone."
  puts 'Run with --dry-run to see what would change.'
  exit 0
end

abort("promotional text is #{NON_SALE_TEXT.length} characters, over Apple's 170") if NON_SALE_TEXT.length > 170

changed = 0
failed = 0
%w[IOS MAC_OS].each do |platform|
  code, body = call(:get, "/v1/apps/#{APP_ID}/appStoreVersions?filter[platform]=#{platform}&limit=10")
  if code != 200
    puts "#{platform}: could not list versions (HTTP #{code})"
    failed += 1
    next
  end
  # The live version is the one users see. Anything still in preparation is checked too, so a
  # sale line cannot ride into the next release.
  versions = (body['data'] || []).select do |v|
    %w[READY_FOR_SALE PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED
       WAITING_FOR_REVIEW].include?(v['attributes']['appStoreState'])
  end
  versions.each do |v|
    label = "#{platform} #{v['attributes']['versionString']} (#{v['attributes']['appStoreState']})"
    lc, lb = call(:get, "/v1/appStoreVersions/#{v['id']}/appStoreVersionLocalizations?limit=50")
    next unless lc == 200

    (lb['data'] || []).each do |loc|
      text = loc['attributes']['promotionalText'].to_s
      unless text =~ SALE_PATTERN
        puts "#{label} #{loc['attributes']['locale']}: no sale line, unchanged"
        next
      end
      puts "#{label} #{loc['attributes']['locale']}: #{text[0, 90].inspect}"
      if DRY_RUN
        puts '  would become the non-sale text (dry run)'
        next
      end
      payload = { 'data' => { 'type' => 'appStoreVersionLocalizations', 'id' => loc['id'],
                              'attributes' => { 'promotionalText' => NON_SALE_TEXT } } }
      pc, pb = call(:patch, "/v1/appStoreVersionLocalizations/#{loc['id']}", payload)
      if pc == 200
        changed += 1
        puts "  replaced (HTTP 200)"
      else
        failed += 1
        errs = (pb['errors'] || []).map { |e| "#{e['code']}: #{e['detail']}" }.join(' | ')
        puts "  HTTP #{pc} #{errs}"
      end
    end
  end
end

puts
puts DRY_RUN ? 'Dry run. Nothing was sent.' : "#{changed} listing(s) changed, #{failed} failure(s)."
exit(failed.zero? ? 0 : 1)
