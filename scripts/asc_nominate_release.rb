#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Nominates a release to Apple's editors for App Store featuring (App Enhancements), from
# fastlane/nominations/<version>.json. Written 2026-10-17 from the App Store Connect API reference
# (POST /v1/nominations, PATCH /v1/nominations/{id}, GET /v1/nominations, read that day) and
# App Store Connect Help, "Nominate your app for featuring" (minimum lead time 3 weeks; a submitted
# nomination can still be edited, except its type and related apps).
#
#   zsh -ic 'ruby scripts/asc_nominate_release.rb 5.7'                    # dry run: lists, sends nothing
#   zsh -ic 'ruby scripts/asc_nominate_release.rb 5.7 --apply'            # saves it as a draft
#   zsh -ic 'ruby scripts/asc_nominate_release.rb 5.7 --apply --submit'   # sends it to Apple's editors
#
# A nomination with the same name already in Drafts or Submitted is updated in place, never duplicated.
# An App Store Connect write happens only at the owner's word. Reads APP_STORE_CONNECT_API_KEY_ID,
# _ISSUER_ID and _API_KEY_PATH, exported by ~/.zshrc, hence `zsh -ic`. Prints no key material.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'time'

APP_ID = '6756559175'
VERSION = ARGV.reject { |a| a.start_with?('--') }.first
abort('usage: asc_nominate_release.rb <version> [--apply [--submit]]') unless VERSION
APPLY = ARGV.include?('--apply')
SUBMIT = ARGV.include?('--submit')
abort('--submit needs --apply') if SUBMIT && !APPLY

SOURCE = File.expand_path("../fastlane/nominations/#{VERSION}.json", __dir__)
abort("no #{SOURCE}") unless File.file?(SOURCE)
SPEC = JSON.parse(File.read(SOURCE, encoding: 'UTF-8'))
%w[name description publishStartDate].each { |k| abort("#{File.basename(SOURCE)} has no #{k}") if SPEC[k].to_s.strip.empty? }
abort('type must be APP_ENHANCEMENTS, APP_LAUNCH or NEW_CONTENT') unless %w[APP_ENHANCEMENTS APP_LAUNCH NEW_CONTENT].include?(SPEC.fetch('type', 'APP_ENHANCEMENTS'))
abort('at most 5 supplemental URLs (App Store Connect Help)') if Array(SPEC['supplementalMaterialsUris']).size > 5
start = Time.parse(SPEC['publishStartDate'])
lead_days = ((start - Time.now) / 86_400).floor
puts "#{SPEC['name']}: publish #{SPEC['publishStartDate']}#{SPEC['publishEndDate'] ? " to #{SPEC['publishEndDate']}" : ''} (#{lead_days} days from now; Apple asks for at least 21)"
puts "description #{SPEC['description'].length} characters, notes #{SPEC['notes'].to_s.length}"
# App Store Connect refused a 1,542-character description on 2026-10-17: "The maximum allowable limit is '1000'".
abort('description is over 1,000 characters, which App Store Connect refuses') if SPEC['description'].length > 1000
# And 585 characters of notes the same day: "The maximum allowable limit is '500'".
abort('notes are over 500 characters, which App Store Connect refuses') if SPEC['notes'].to_s.length > 500

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

# This app's nominations that are still open, by state.
existing = nil
%w[DRAFT SUBMITTED].each do |state|
  code, body = call(:get, "/v1/nominations?filter[state]=#{state}&filter[relatedApps]=#{APP_ID}&limit=200" \
                          '&fields[nominations]=name,type,state,publishStartDate,publishEndDate,submittedDate')
  abort("list #{state} #{problem(code, body)}") unless code == 200
  (body['data'] || []).each do |n|
    a = n['attributes']
    puts "  #{a['state']}: #{a['name']} (#{a['type']}, publish #{a['publishStartDate']}#{a['submittedDate'] ? ", submitted #{a['submittedDate']}" : ''})"
    existing ||= n if a['name'] == SPEC['name']
  end
end

attributes = {
  'name' => SPEC['name'],
  'type' => SPEC.fetch('type', 'APP_ENHANCEMENTS'),
  'description' => SPEC['description'],
  'notes' => SPEC['notes'],
  'deviceFamilies' => SPEC['deviceFamilies'],
  'locales' => SPEC['locales'],
  'publishStartDate' => start.utc.iso8601,
  'publishEndDate' => SPEC['publishEndDate'] ? Time.parse(SPEC['publishEndDate']).utc.iso8601 : nil,
  'hasInAppEvents' => SPEC.fetch('hasInAppEvents', false),
  'preOrderEnabled' => SPEC.fetch('preOrderEnabled', false),
  'launchInSelectMarketsFirst' => SPEC.fetch('launchInSelectMarketsFirst', false),
  'supplementalMaterialsUris' => SPEC['supplementalMaterialsUris'],
  'submitted' => SUBMIT
}.reject { |_, v| v.nil? }

unless APPLY
  puts existing ? "would update #{SPEC['name']} (#{existing['attributes']['state']}) in place" : "would create #{SPEC['name']} as a draft"
  puts 'Dry run. Add --apply to save it as a draft, and --submit as well to send it to Apple.'
  exit 0
end

if existing
  # A submitted nomination keeps its type and related apps (App Store Connect Help); leave both out of the update,
  # and never take a submitted one back to a draft.
  update = attributes.reject { |k, _| k == 'type' }
  update.delete('submitted') if existing['attributes']['state'] == 'SUBMITTED'
  code, body = call(:patch, "/v1/nominations/#{existing['id']}",
                    { 'data' => { 'type' => 'nominations', 'id' => existing['id'], 'attributes' => update } })
else
  code, body = call(:post, '/v1/nominations',
                    { 'data' => { 'type' => 'nominations', 'attributes' => attributes,
                                  'relationships' => { 'relatedApps' => { 'data' => [{ 'type' => 'apps', 'id' => APP_ID }] } } } })
end
msg = problem(code, body)
abort("#{existing ? 'update' : 'create'} #{msg}") if msg
a = body.dig('data', 'attributes') || {}
puts "#{existing ? 'updated' : 'created'}: #{a['name']} state=#{a['state']} publish=#{a['publishStartDate']}#{a['publishEndDate'] ? " to #{a['publishEndDate']}" : ''} id=#{body.dig('data', 'id')}"
