#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Creates one win-back offer per Pro subscription, in every territory.
#
# WHY
#
# App Store Connect data on 2026-09-22: three Pro Monthly subscribers cancelled at 24, 26 and
# 31 days, and every one of the five cancel-sheet views ended in a cancel. Nothing was offered to
# anyone who lapsed. Published guidance on discounting is consistent that the cohort worth a
# discount is the one that already paid and left, not new installs; a win-back offer is exactly
# that cohort, and Apple presents it itself, on the App Store and in the app on launch, with no
# code in the app. See Docs/Release/CONVERSION_AND_REVIEWS_2026-09.md, sections 3 and 5.
#
# THE OFFERS
#
#   Pro Monthly  $2.99 a month for the first 3 months, then $5.99   (PAY_AS_YOU_GO, ONE_MONTH x 3)
#   Pro Annual   $19.99 for the first year, then $29.99             (PAY_UP_FRONT, ONE_YEAR x 1)
#
# Eligibility, both: paid for at least 1 month; lapsed between 1 and 12 months; at most one such
# offer every 12 months. Runs from two days after the script is run, for one year. Priority NORMAL (Apple accepts only HIGH or NORMAL; the docs summary that said MEDIUM was wrong, 409 on 2026-09-22). Apple generates the
# promotional assets. Prices are the USA price point plus every territory Apple equalizes it to,
# so the offer exists everywhere the subscription does.
#
# Both offers can be deactivated in App Store Connect at any time; neither changes the base price.
#
# Usage:
#   zsh -ic 'ruby scripts/asc_winback_offers.rb'           # dry run: shows what would be created
#   zsh -ic 'ruby scripts/asc_winback_offers.rb --apply'   # creates them
#
# Idempotent: a subscription that already has an offer with the same offerId is skipped.
# Reads APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID and _API_KEY_PATH, exported by ~/.zshrc, hence
# `zsh -ic`. Prints no key material. Ruby 2.6 compatible.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'

APPLY = ARGV.include?('--apply')

# Apple requires the start date to be at least a day ahead of its own clock ('needs to be on
# or after 2026-09-24' when run on 2026-09-22 Pacific), so it is computed, two days out, in UTC.
require 'date'
START_DATE = (Date.today + 2).iso8601
END_DATE = (Date.today + 2 + 365).iso8601

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
  request = verb == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
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

# The USA price point plus every territory Apple equalizes it to.
def all_territory_points(usa_point_id)
  ids = []
  path = "/v1/subscriptionPricePoints/#{usa_point_id}/equalizations?limit=200"
  loop do
    code, body = call(:get, path)
    abort("equalizations HTTP #{code}: #{body.to_json[0, 200]}") unless code == 200
    ids += (body['data'] || []).map { |p| p['id'] }
    nxt = body.dig('links', 'next')
    break unless nxt

    path = nxt.sub('https://api.appstoreconnect.apple.com', '')
  end
  ([usa_point_id] + ids).uniq
end

OFFERS = [
  { subscription: '6756639030', name: 'Pro Monthly', reference: 'Win-back Monthly 2026',
    offer_id: 'winback_monthly_2026',
    usa_point: 'eyJzIjoiNjc1NjYzOTAzMCIsInQiOiJVU0EiLCJwIjoiMTAwMzYifQ', usa_price: '$2.99 (regular $5.99)',
    duration: 'ONE_MONTH', mode: 'PAY_AS_YOU_GO', periods: 3 },
  { subscription: '6756638919', name: 'Pro Annual', reference: 'Win-back Annual 2026',
    offer_id: 'winback_annual_2026',
    usa_point: 'eyJzIjoiNjc1NjYzODkxOSIsInQiOiJVU0EiLCJwIjoiMTAxNzcifQ', usa_price: '$19.99 (regular $29.99)',
    duration: 'ONE_YEAR', mode: 'PAY_UP_FRONT', periods: 1 }
].freeze

failures = 0
OFFERS.each do |o|
  code, existing = call(:get, "/v1/subscriptions/#{o[:subscription]}/winBackOffers?limit=20")
  if code == 200 && (existing['data'] || []).any? { |x| x['attributes']['offerId'] == o[:offer_id] }
    puts "#{o[:name]}: offer #{o[:offer_id]} already exists, skipped"
    next
  end

  points = all_territory_points(o[:usa_point])
  puts "#{o[:name]}: #{o[:usa_price]}, #{o[:mode]} #{o[:duration]} x#{o[:periods]}, #{points.size} territories"
  unless APPLY
    puts '  dry run, nothing sent'
    next
  end

  included = points.each_with_index.map do |pid, i|
    { 'type' => 'winBackOfferPrices', 'id' => "${price-#{i}}",
      'relationships' => { 'subscriptionPricePoint' => { 'data' => { 'type' => 'subscriptionPricePoints', 'id' => pid } } } }
  end
  body = { 'data' => {
    'type' => 'winBackOffers',
    'attributes' => {
      'referenceName' => o[:reference], 'offerId' => o[:offer_id],
      'startDate' => START_DATE, 'endDate' => END_DATE,
      'priority' => 'NORMAL', 'promotionIntent' => 'USE_AUTO_GENERATED_ASSETS',
      'duration' => o[:duration], 'offerMode' => o[:mode], 'periodCount' => o[:periods],
      'customerEligibilityPaidSubscriptionDurationInMonths' => 1,
      'customerEligibilityTimeSinceLastSubscribedInMonths' => { 'minimum' => 1, 'maximum' => 12 },
      'customerEligibilityWaitBetweenOffersInMonths' => 12
    },
    'relationships' => {
      'subscription' => { 'data' => { 'type' => 'subscriptions', 'id' => o[:subscription] } },
      'prices' => { 'data' => included.map { |x| { 'type' => 'winBackOfferPrices', 'id' => x['id'] } } }
    }
  }, 'included' => included }

  code, response = call(:post, '/v1/winBackOffers', body)
  if code == 201
    puts "  created, id #{response['data']['id']}"
  else
    failures += 1
    errors = (response['errors'] || []).map { |e| "#{e['code']}: #{e['detail']}" }.join(' | ')
    puts "  HTTP #{code} #{errors.empty? ? response.to_json[0, 300] : errors}"
  end
end

puts
puts APPLY ? "#{failures.zero? ? 'Done.' : "#{failures} failed."}" : 'Dry run. Run with --apply to create the offers.'
exit(failures.zero? ? 0 : 1)
