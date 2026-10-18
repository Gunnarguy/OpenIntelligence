#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Uploads a version's App Store product page header and search result image through the App Asset Library, and places
# them on the iOS version's en-US localization. Written 2026-10-17 from the App Store Connect API reference read that
# day ("Uploading and managing image assets", "Placing assets on your App Store surfaces", the reference data):
# reserve with POST /v1/appAssetLibraryImages, send the bytes to the upload operations, commit with uploaded: true, wait
# for PREPARE_FOR_SUBMISSION, then POST /v1/appAssetLibraryPlacements with the group DEFAULT_PROFILE (one of each type
# per localization).
#
#   zsh -ic 'ruby scripts/asc_upload_listing_art.rb 5.7 <header.png> <search.png>'           # dry run: reads only
#   zsh -ic 'ruby scripts/asc_upload_listing_art.rb 5.7 <header.png> <search.png> --apply'   # uploads and places
#
# The header must be 3840x1646 PNG and the search image 3:2, 1920 to 3840 wide, PNG or JPEG, neither with alpha (the
# reference data's imageSpecs, read 2026-10-17). A localization that already has a placement of a type is left alone.
# An App Store Connect write happens only at the owner's word. Reads APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID and
# _API_KEY_PATH, exported by ~/.zshrc, hence `zsh -ic`. Prints no key material.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'

APP_ID = '6756559175'
args = ARGV.reject { |a| a.start_with?('--') }
abort('usage: asc_upload_listing_art.rb <version> <header.png> <search.png> [--apply]') unless args.size == 3
VERSION, HEADER, SEARCH = args
APPLY = ARGV.include?('--apply')
[HEADER, SEARCH].each { |f| abort("no #{f}") unless File.file?(f) }

# The two placements, each with the image specification App Store Connect should match the file to.
ART = [
  { file: HEADER, type: 'PRODUCT_PAGE_HEADER_ASSET', spec: '1eb43b80-e0b7-4d96-bd32-47a42a8c5fed',
    name: "OpenIntelligence #{VERSION} product page header" },
  { file: SEARCH, type: 'APP_STORE_SEARCH_RESULTS_ASSET', spec: 'd2ffa3b7-6c55-5cdf-8512-229d92791333',
    name: "OpenIntelligence #{VERSION} search result" }
].freeze

def png_size(path)
  bytes = File.binread(path, 33)
  return nil unless bytes&.start_with?("\x89PNG".b)

  width, height = bytes[16, 8].unpack('NN')
  alpha = [4, 6].include?(bytes.getbyte(25)) # color types with an alpha channel
  [width, height, alpha]
end

header = png_size(HEADER)
abort("#{HEADER} must be a 3840x1646 PNG with no alpha") unless header && header[0, 2] == [3840, 1646] && !header[2]
search = png_size(SEARCH)
unless search && search[0].between?(1920, 3840) && search[0] * 2 == search[1] * 3 && !search[2]
  abort("#{SEARCH} must be a 3:2 PNG, 1920 to 3840 wide, with no alpha")
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
  der = OpenSSL::PKey::EC.new(File.read(KEY_PATH)).sign(OpenSSL::Digest.new('SHA256'), signing)
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
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(request) }
  parsed = response.body.to_s.empty? ? {} : (JSON.parse(response.body) rescue { 'raw' => response.body.to_s[0, 300] })
  [response.code.to_i, parsed]
end

def problem(code, body)
  return nil if code.between?(200, 299)

  errs = (body['errors'] || []).map { |e| "#{e['code']}: #{e['detail']}" }
  "HTTP #{code} #{errs.empty? ? body.to_json[0, 300] : errs.join(' | ')}"
end

def must(code, body, what)
  msg = problem(code, body)
  abort("#{what}: #{msg}") if msg
  body
end

# The iOS version's en-US localization, and what is already placed on it.
body = must(*call(:get, "/v1/apps/#{APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=#{VERSION}&limit=1"),
            'version')
version = (body['data'] || []).first or abort("no iOS #{VERSION} in App Store Connect")
state = version.dig('attributes', 'appStoreState')
body = must(*call(:get, "/v1/appStoreVersions/#{version['id']}/appStoreVersionLocalizations?limit=50"), 'localizations')
loc = (body['data'] || []).find { |l| l.dig('attributes', 'locale') == 'en-US' } or abort('no en-US localization')
body = must(*call(:get, "/v1/appStoreVersionLocalizations/#{loc['id']}/placements?limit=200"), 'placements')
placed = (body['data'] || []).map { |p| p.dig('attributes', 'placementType') }.tally
puts "iOS #{VERSION} (#{state}), en-US localization #{loc['id']}: placements #{placed}"
library = must(*call(:get, "/v1/apps/#{APP_ID}/assetLibrary"), 'asset library').dig('data', 'id')
puts "asset library #{library}"

todo = ART.reject do |art|
  next false unless placed[art[:type]].to_i.positive?

  puts "#{art[:type]}: already placed on this localization; left alone"
  true
end
todo.each { |art| puts "would upload #{File.basename(art[:file])} (#{File.size(art[:file])} bytes) as #{art[:type]}" }
unless APPLY
  puts 'Dry run. Add --apply to upload and place them.'
  exit 0
end

todo.each do |art|
  size = File.size(art[:file])
  reserve = {
    'data' => {
      'type' => 'appAssetLibraryImages',
      'attributes' => { 'fileName' => File.basename(art[:file]), 'fileSize' => size, 'category' => 'CREATIVE_ASSETS',
                        'referenceName' => art[:name] },
      'relationships' => { 'assetLibrary' => { 'data' => { 'type' => 'appAssetLibraries', 'id' => library } } }
    }
  }
  image = must(*call(:post, '/v1/appAssetLibraryImages', reserve), "reserve #{art[:type]}")['data']
  bytes = File.binread(art[:file])
  (image.dig('attributes', 'uploadOperations') || []).each do |op|
    uri = URI(op['url'])
    request = Net::HTTPGenericRequest.new(op['method'], true, true, uri.request_uri)
    (op['requestHeaders'] || []).each { |h| request[h['name']] = h['value'] }
    request.body = bytes.byteslice(op['offset'], op['length'])
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(request) }
    abort("upload #{art[:type]}: HTTP #{response.code}") unless response.code.to_i.between?(200, 299)
  end
  must(*call(:patch, "/v1/appAssetLibraryImages/#{image['id']}",
             { 'data' => { 'type' => 'appAssetLibraryImages', 'id' => image['id'], 'attributes' => { 'uploaded' => true } } }),
       "commit #{art[:type]}")
  attrs = nil
  60.times do
    sleep 5
    attrs = must(*call(:get, "/v1/appAssetLibraryImages/#{image['id']}"), "read #{art[:type]}").dig('data', 'attributes')
    break unless %w[AWAITING_UPLOAD UPLOAD_COMPLETE].include?(attrs['state'])
  end
  abort("#{art[:type]}: processing ended #{attrs['state']} #{attrs['stateDetails'].to_json}") unless attrs['state'] == 'PREPARE_FOR_SUBMISSION'
  abort("#{art[:type]}: matched spec #{attrs['specId']}, expected #{art[:spec]}") unless attrs['specId'] == art[:spec]
  placement = {
    'data' => {
      'type' => 'appAssetLibraryPlacements',
      'attributes' => { 'placementType' => art[:type], 'placementGroup' => 'DEFAULT_PROFILE' },
      'relationships' => {
        'image' => { 'data' => { 'type' => 'appAssetLibraryImages', 'id' => image['id'] } },
        'appStoreVersionLocalization' => { 'data' => { 'type' => 'appStoreVersionLocalizations', 'id' => loc['id'] } }
      }
    }
  }
  placed_now = must(*call(:post, '/v1/appAssetLibraryPlacements', placement), "place #{art[:type]}")['data']
  puts "#{art[:type]}: image #{image['id']} (#{attrs.dig('imageAsset', 'width')}x#{attrs.dig('imageAsset', 'height')}), " \
       "placement #{placed_now['id']} #{placed_now.dig('attributes', 'state')}"
end
