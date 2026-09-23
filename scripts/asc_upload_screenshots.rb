#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Replaces the iPhone and iPad screenshot sets on an unsubmitted App Store version.
#
# Files come from a folder named like scripts/compose_store_screenshots.py writes them:
#   iphone67-<n>-<scene>.png  -> APP_IPHONE_67      (1320x2868)
#   iphone65-<n>-<scene>.png  -> APP_IPHONE_65      (1284x2778)
#   iphone61-<n>-<scene>.png  -> APP_IPHONE_61      (1206x2622)
#   ipad129-<n>-<scene>.png   -> APP_IPAD_PRO_3GEN_129 (2048x2732)
# <n> sets the order on the listing.
#
# Safe order: every new image is uploaded and confirmed COMPLETE before any old one is deleted,
# so a failed run leaves the old set in place rather than an empty one. A version that is live
# or in review has locked screenshots; the script refuses anything but PREPARE_FOR_SUBMISSION.
# iPad sets live on the iOS version record.
#
# Usage:
#   zsh -ic 'ruby scripts/asc_upload_screenshots.rb 5.4 <folder>'           # dry run
#   zsh -ic 'ruby scripts/asc_upload_screenshots.rb 5.4 <folder> --apply'
#
# Reads APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID and _API_KEY_PATH, exported by ~/.zshrc, hence
# `zsh -ic`. Prints no key material. Ruby 2.6 compatible.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'digest'

APP_ID = '6756559175'
VERSION, FOLDER = ARGV.reject { |a| a.start_with?('--') }
abort('usage: asc_upload_screenshots.rb <version> <folder> [--apply]') unless VERSION && FOLDER && Dir.exist?(FOLDER)
APPLY = ARGV.include?('--apply')
SETS = {
  'iphone67' => 'APP_IPHONE_67', 'iphone65' => 'APP_IPHONE_65',
  'iphone61' => 'APP_IPHONE_61', 'ipad129' => 'APP_IPAD_PRO_3GEN_129'
}.freeze

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
  klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.fetch(verb)
  request = klass.new(uri)
  request['Authorization'] = 'Bearer ' + token
  if body
    request['Content-Type'] = 'application/json'
    request.body = body.to_json
  end
  response = Net::HTTP.start(uri.host, uri.port, :use_ssl => true, :read_timeout => 120) { |h| h.request(request) }
  parsed = begin
    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  rescue StandardError
    { 'raw' => response.body.to_s[0, 300] }
  end
  [response.code.to_i, parsed]
end

def ok!(what, code, body)
  return if code.between?(200, 299)
  errs = (body['errors'] || []).map { |e| "#{e['code']}: #{e['detail']}" }.join(' | ')
  abort("#{what}: HTTP #{code} #{errs.empty? ? body.to_json[0, 300] : errs}")
end

def upload(set_id, path)
  bytes = File.binread(path)
  code, created = call(:post, '/v1/appScreenshots', {
    'data' => { 'type' => 'appScreenshots',
                'attributes' => { 'fileName' => File.basename(path), 'fileSize' => bytes.bytesize },
                'relationships' => { 'appScreenshotSet' => { 'data' => { 'type' => 'appScreenshotSets', 'id' => set_id } } } }
  })
  ok!("reserve #{File.basename(path)}", code, created)
  shot_id = created['data']['id']
  created['data']['attributes']['uploadOperations'].each do |op|
    uri = URI(op['url'])
    put = Net::HTTP.const_get(op['method'].capitalize).new(uri)
    (op['requestHeaders'] || []).each { |h| put[h['name']] = h['value'] }
    put.body = bytes.byteslice(op['offset'], op['length'])
    res = Net::HTTP.start(uri.host, uri.port, :use_ssl => true, :read_timeout => 120) { |h| h.request(put) }
    abort("upload part of #{File.basename(path)}: HTTP #{res.code}") unless res.code.to_i.between?(200, 299)
  end
  code, body = call(:patch, "/v1/appScreenshots/#{shot_id}", {
    'data' => { 'type' => 'appScreenshots', 'id' => shot_id,
                'attributes' => { 'uploaded' => true, 'sourceFileChecksum' => Digest::MD5.hexdigest(bytes) } }
  })
  ok!("commit #{File.basename(path)}", code, body)
  60.times do
    code, body = call(:get, "/v1/appScreenshots/#{shot_id}")
    state = body.dig('data', 'attributes', 'assetDeliveryState', 'state')
    return shot_id if state == 'COMPLETE'
    abort("#{File.basename(path)} FAILED: #{body.dig('data', 'attributes', 'assetDeliveryState', 'errors').to_json}") if state == 'FAILED'
    sleep 3
  end
  abort("#{File.basename(path)} never reached COMPLETE")
end

code, versions = call(:get, "/v1/apps/#{APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=#{VERSION}&limit=1")
version = (versions['data'] || []).first or abort("no iOS #{VERSION} version")
state = version['attributes']['appStoreState']
abort("iOS #{VERSION} is #{state}; screenshots are only editable in PREPARE_FOR_SUBMISSION") unless state == 'PREPARE_FOR_SUBMISSION'
code, locs = call(:get, "/v1/appStoreVersions/#{version['id']}/appStoreVersionLocalizations?limit=10")
loc = (locs['data'] || []).find { |l| l['attributes']['locale'] == 'en-US' } or abort('no en-US localization')
code, sets = call(:get, "/v1/appStoreVersionLocalizations/#{loc['id']}/appScreenshotSets?limit=50")
set_by_type = (sets['data'] || []).each_with_object({}) { |s, h| h[s['attributes']['screenshotDisplayType']] = s['id'] }

SETS.each do |prefix, type|
  files = Dir[File.join(FOLDER, "#{prefix}-*.png")].sort_by { |f| File.basename(f)[/-(\d+)-/, 1].to_i }
  next puts("#{type}: no files, skipped") if files.empty?
  set_id = set_by_type[type] or abort("#{type}: no screenshot set on the 5.4 record")
  code, old = call(:get, "/v1/appScreenshotSets/#{set_id}/appScreenshots?limit=20")
  old_ids = (old['data'] || []).map { |s| s['id'] }
  puts "#{type}: #{files.size} new, replacing #{old_ids.size} old"
  next unless APPLY

  new_ids = files.map { |f| id = upload(set_id, f); puts "  uploaded #{File.basename(f)}"; id }
  old_ids.each { |id| code, body = call(:delete, "/v1/appScreenshots/#{id}"); ok!("delete old #{id}", code, body) }
  code, body = call(:patch, "/v1/appScreenshotSets/#{set_id}/relationships/appScreenshots",
                    { 'data' => new_ids.map { |id| { 'type' => 'appScreenshots', 'id' => id } } })
  ok!("order #{type}", code, body)
  puts "  #{old_ids.size} old removed, order set"
end
puts APPLY ? 'Done. Nothing was submitted.' : 'Dry run. Add --apply to upload.'
