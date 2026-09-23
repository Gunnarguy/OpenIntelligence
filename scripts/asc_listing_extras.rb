#!/usr/bin/env ruby
# frozen_string_literal: true
#
# The App Store Connect work that asc_prepare_release.rb does not do, for one version on iOS and
# macOS. It never submits anything for review, and it is safe to run twice: every step reads first
# and changes only what differs.
#
#   1. App Review notes: appends fastlane/review_notes/<version>.txt unless the notes already hold it.
#   2. Promotional text: while the Lifetime sale runs (through SALE_LAST_DAY), copies the live
#      version's sale line onto <version>, so releasing <version> mid-sale does not drop the sale
#      from the store page. scripts/asc_end_sale.rb takes the sale line off whichever version is
#      live on 2026-09-30, so nothing here has to be undone by hand.
#   3. Product descriptions: sets the Pro subscriptions and the Lifetime purchase to QuotaPolicy's
#      limits. Apple has refused edits to approved products before (409 UNMODIFIABLE); the answer is
#      printed as it comes back, and the web page is the fallback.
#   4. Subscription images: uploads fastlane/iap_images/<productId>.png to each subscription that has
#      none. A win-back offer needs an approved image before the App Store will promote it. The
#      image is reviewed with the next submission; this script does not submit it.
#
# Usage:
#   zsh -ic 'ruby scripts/asc_listing_extras.rb 5.4'            # dry run: reads, prints, changes nothing
#   zsh -ic 'ruby scripts/asc_listing_extras.rb 5.4 --apply'
#
# Reads APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID and _API_KEY_PATH, exported by ~/.zshrc, hence
# `zsh -ic`. Prints no key material. Files are read as UTF-8 explicitly: a non-interactive shell
# defaults to US-ASCII. Ruby 2.6 compatible.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'digest'
require 'date'

APP_ID = '6756559175'
VERSION = ARGV.reject { |a| a.start_with?('--') }.first
abort('usage: asc_listing_extras.rb <version> [--apply]') unless VERSION
APPLY = ARGV.include?('--apply')
ROOT = File.expand_path('..', __dir__)
NOTES_FILE = File.join(ROOT, 'fastlane', 'review_notes', "#{VERSION}.txt")
IMAGE_DIR = File.join(ROOT, 'fastlane', 'iap_images')

# The launch sale's last day, the same date scripts/asc_end_sale.rb uses.
SALE_LAST_DAY = Date.new(2026, 9, 29)
SALE_PATTERN = /\bon sale\b|%\s*off\b|\boff until\b|\blaunch (price|sale|discount)\b/i

# QuotaPolicy.swift: Pro is 1,000 documents and 10 libraries; Lifetime is unlimited documents and
# 20 libraries. Apple's limit for these descriptions is 55 characters.
DESCRIPTIONS = {
  'pro_annual' => 'Annual billing for 1,000 documents and 10 libraries.',
  'pro_monthly' => 'Monthly billing for 1,000 documents and 10 libraries.',
  'lifetime_cohort' => 'Permanent Pro - 20 Libraries + Unlimited Documents'
}.freeze
DESCRIPTIONS.each { |id, text| abort("#{id} description is #{text.length} characters, limit 55") if text.length > 55 }

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
  request = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(verb).new(uri)
  request['Authorization'] = 'Bearer ' + token
  if body
    request['Content-Type'] = 'application/json'
    request.body = body.to_json
  end
  response = Net::HTTP.start(uri.host, uri.port, :use_ssl => true, :read_timeout => 120) { |h| h.request(request) }
  parsed = begin
    response.body.to_s.empty? ? {} : JSON.parse(response.body.force_encoding('UTF-8'))
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

$failures = 0
$refusals = 0

def result(label, code, body)
  msg = problem(code, body)
  if msg.nil?
    puts "  #{label}: done (HTTP #{code})"
  elsif code == 409
    $refusals += 1
    puts "  #{label}: refused by Apple, #{msg}"
  else
    $failures += 1
    puts "  #{label}: FAILED, #{msg}"
  end
end

def version_record(platform)
  _, body = call(:get, "/v1/apps/#{APP_ID}/appStoreVersions?filter[platform]=#{platform}&filter[versionString]=#{VERSION}&limit=1")
  (body['data'] || []).first
end

def en_us_localization(version_id)
  _, body = call(:get, "/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations?limit=20")
  (body['data'] || []).find { |l| l['attributes']['locale'] == 'en-US' }
end

puts APPLY ? "Applying to #{VERSION}. Nothing is submitted." : "Dry run for #{VERSION}. Nothing is sent."

# 1. App Review notes -----------------------------------------------------------------------------
puts "\n1. App Review notes (#{File.basename(NOTES_FILE)})"
addition = File.read(NOTES_FILE, encoding: 'UTF-8').strip
%w[IOS MAC_OS].each do |platform|
  record = version_record(platform)
  next puts("  #{platform}: no #{VERSION} record") || ($failures += 1) unless record
  code, detail = call(:get, "/v1/appStoreVersions/#{record['id']}/appStoreReviewDetail")
  data = detail['data']
  next puts("  #{platform}: no review detail (#{problem(code, detail) || 'empty'})") || ($failures += 1) unless data
  notes = data['attributes']['notes'].to_s
  next puts("  #{platform}: already carries the #{VERSION} addition") if notes.include?(addition)
  updated = notes.strip.empty? ? addition : "#{notes.rstrip}\n\n#{addition}"
  next puts("  #{platform}: notes would be #{updated.length} characters, limit 4000") || ($failures += 1) if updated.length > 4000
  if APPLY
    code, body = call(:patch, "/v1/appStoreReviewDetails/#{data['id']}",
                      { 'data' => { 'type' => 'appStoreReviewDetails', 'id' => data['id'], 'attributes' => { 'notes' => updated } } })
    result("#{platform} notes (#{notes.length} to #{updated.length} characters)", code, body)
  else
    puts "  #{platform}: would append #{addition.length} characters to #{notes.length} (dry run)"
  end
end

# 2. Promotional text -----------------------------------------------------------------------------
puts "\n2. Promotional text"
if Date.today > SALE_LAST_DAY
  puts "  The sale ended #{SALE_LAST_DAY}; promotional text is left alone."
else
  %w[IOS MAC_OS].each do |platform|
    _, versions = call(:get, "/v1/apps/#{APP_ID}/appStoreVersions?filter[platform]=#{platform}&limit=200")
    live = (versions['data'] || []).find { |v| v['attributes']['appStoreState'] == 'READY_FOR_SALE' }
    target = (versions['data'] || []).find { |v| v['attributes']['versionString'] == VERSION }
    next puts("  #{platform}: no live version or no #{VERSION} record") || ($failures += 1) unless live && target
    live_text = en_us_localization(live['id'])&.dig('attributes', 'promotionalText').to_s.strip
    target_loc = en_us_localization(target['id'])
    next puts("  #{platform}: no en-US localization on #{VERSION}") || ($failures += 1) unless target_loc
    current = target_loc['attributes']['promotionalText'].to_s.strip
    next puts("  #{platform}: live #{live['attributes']['versionString']} carries no sale line; nothing to copy") unless live_text =~ SALE_PATTERN
    next puts("  #{platform}: #{VERSION} already carries the sale line") if current == live_text
    if APPLY
      code, body = call(:patch, "/v1/appStoreVersionLocalizations/#{target_loc['id']}",
                        { 'data' => { 'type' => 'appStoreVersionLocalizations', 'id' => target_loc['id'],
                                      'attributes' => { 'promotionalText' => live_text } } })
      result("#{platform} promotional text", code, body)
    else
      puts "  #{platform}: would copy #{live_text.inspect} (dry run)"
    end
  end
end

# 3 and 4. Products: descriptions and subscription images -----------------------------------------
subscriptions = {}
_, groups = call(:get, "/v1/apps/#{APP_ID}/subscriptionGroups?limit=20")
(groups['data'] || []).each do |group|
  _, subs = call(:get, "/v1/subscriptionGroups/#{group['id']}/subscriptions?limit=50")
  (subs['data'] || []).each { |s| subscriptions[s['attributes']['productId']] = s['id'] }
end
_, iaps = call(:get, "/v1/apps/#{APP_ID}/inAppPurchasesV2?limit=50")
purchases = (iaps['data'] || []).each_with_object({}) { |p, h| h[p['attributes']['productId']] = p['id'] }

puts "\n3. Product descriptions"
DESCRIPTIONS.each do |product, text|
  if subscriptions[product]
    _, locs = call(:get, "/v1/subscriptions/#{subscriptions[product]}/subscriptionLocalizations?limit=20")
    type, path = 'subscriptionLocalizations', '/v1/subscriptionLocalizations/'
  elsif purchases[product]
    _, locs = call(:get, "/v2/inAppPurchases/#{purchases[product]}/inAppPurchaseLocalizations?limit=20")
    type, path = 'inAppPurchaseLocalizations', '/v1/inAppPurchaseLocalizations/'
  else
    puts "  #{product}: not found"
    $failures += 1
    next
  end
  loc = (locs['data'] || []).find { |l| l['attributes']['locale'] == 'en-US' }
  next puts("  #{product}: no en-US localization") || ($failures += 1) unless loc
  current = loc['attributes']['description'].to_s
  next puts("  #{product}: already #{text.inspect}") if current == text
  if APPLY
    code, body = call(:patch, "#{path}#{loc['id']}",
                      { 'data' => { 'type' => type, 'id' => loc['id'], 'attributes' => { 'description' => text } } })
    result("#{product} #{current.inspect} to #{text.inspect}", code, body)
  else
    puts "  #{product}: would change #{current.inspect} to #{text.inspect} (dry run)"
  end
end

puts "\n4. Subscription images (#{IMAGE_DIR.sub(ROOT + '/', '')})"
subscriptions.each do |product, sub_id|
  file = File.join(IMAGE_DIR, "#{product}.png")
  next puts("  #{product}: no image file; skipped") unless File.exist?(file)
  _, images = call(:get, "/v1/subscriptions/#{sub_id}/images?limit=10")
  existing = (images['data'] || []).map { |i| "#{i.dig('attributes', 'fileName')} (#{i.dig('attributes', 'state')})" }
  next puts("  #{product}: already has #{existing.join(', ')}") unless existing.empty?
  bytes = File.binread(file)
  unless APPLY
    puts "  #{product}: would upload #{File.basename(file)}, #{bytes.bytesize} bytes (dry run)"
    next
  end
  code, created = call(:post, '/v1/subscriptionImages', {
    'data' => { 'type' => 'subscriptionImages',
                'attributes' => { 'fileName' => File.basename(file), 'fileSize' => bytes.bytesize },
                'relationships' => { 'subscription' => { 'data' => { 'type' => 'subscriptions', 'id' => sub_id } } } }
  })
  if problem(code, created)
    result("#{product} image reservation", code, created)
    next
  end
  image_id = created['data']['id']
  upload_failed = false
  (created['data']['attributes']['uploadOperations'] || []).each do |op|
    uri = URI(op['url'])
    put = Net::HTTP.const_get(op['method'].capitalize).new(uri)
    (op['requestHeaders'] || []).each { |h| put[h['name']] = h['value'] }
    put.body = bytes.byteslice(op['offset'], op['length'])
    res = Net::HTTP.start(uri.host, uri.port, :use_ssl => true, :read_timeout => 120) { |h| h.request(put) }
    next if res.code.to_i.between?(200, 299)
    puts "  #{product}: upload part FAILED, HTTP #{res.code}"
    upload_failed = true
    $failures += 1
    break
  end
  next if upload_failed
  code, body = call(:patch, "/v1/subscriptionImages/#{image_id}", {
    'data' => { 'type' => 'subscriptionImages', 'id' => image_id,
                'attributes' => { 'uploaded' => true, 'sourceFileChecksum' => Digest::MD5.hexdigest(bytes) } }
  })
  if problem(code, body)
    result("#{product} image commit", code, body)
    next
  end
  state = nil
  20.times do
    _, got = call(:get, "/v1/subscriptionImages/#{image_id}")
    state = got.dig('data', 'attributes', 'state')
    break unless %w[AWAITING_UPLOAD UPLOAD_COMPLETE].include?(state)
    sleep 3
  end
  $failures += 1 if state == 'FAILED'
  puts "  #{product}: uploaded #{File.basename(file)}, state #{state}"
end

puts
if !APPLY
  puts 'Dry run. Add --apply to write.'
elsif $failures.zero?
  puts "Done. #{$refusals} change(s) refused by Apple are listed above. Nothing was submitted."
else
  puts "#{$failures} problem(s) above. Nothing was submitted."
end
exit($failures.zero? ? 0 : 1)
