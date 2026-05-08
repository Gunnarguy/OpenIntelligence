#!/usr/bin/env ruby
# Push metadata directly to App Store Connect API, bypassing fastlane deliver's
# broken edit_live support.
#
# Usage: ruby scripts/push_metadata.rb

require "jwt"
require "openssl"
require "net/http"
require "json"
require "uri"
require_relative "app_store_connect_env"

# ── Config ──────────────────────────────────────────────────────────────────
KEY_PATH   = AppStoreConnectEnv.required_path("APP_STORE_CONNECT_PRIVATE_KEY_PATH", "APP_STORE_CONNECT_API_KEY_PATH", "ASC_KEY_PATH")
KEY_ID     = AppStoreConnectEnv.required_value("APP_STORE_CONNECT_KEY_ID", "APP_STORE_CONNECT_API_KEY_ID", "ASC_KEY_ID")
ISSUER_ID  = AppStoreConnectEnv.required_value("APP_STORE_CONNECT_ISSUER", "APP_STORE_CONNECT_ISSUER_ID", "ASC_ISSUER_ID")
BUNDLE_ID  = "Gunndamental.OpenIntelligence"
METADATA   = File.join(__dir__, "..", "fastlane", "metadata", "en-US")
BASE_URL   = "https://api.appstoreconnect.apple.com/v1"

# ── JWT ─────────────────────────────────────────────────────────────────────
def make_token
  key = OpenSSL::PKey::EC.new(File.read(KEY_PATH))
  now = Time.now.to_i
  payload = { iss: ISSUER_ID, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" }
  JWT.encode(payload, key, "ES256", { kid: KEY_ID })
end

TOKEN = make_token

# ── HTTP helpers ────────────────────────────────────────────────────────────
def api_get(path)
  uri = URI("#{BASE_URL}#{path}")
  req = Net::HTTP::Get.new(uri)
  req["Authorization"] = "Bearer #{TOKEN}"
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  unless res.code.start_with?("2")
    abort "GET #{path} → #{res.code}\n#{res.body}"
  end
  JSON.parse(res.body)
end

def api_patch(path, body)
  uri = URI("#{BASE_URL}#{path}")
  req = Net::HTTP::Patch.new(uri)
  req["Authorization"] = "Bearer #{TOKEN}"
  req["Content-Type"] = "application/json"
  req.body = body.to_json
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  unless res.code.start_with?("2")
    abort "PATCH #{path} → #{res.code}\n#{res.body}"
  end
  JSON.parse(res.body)
end

# ── Read local metadata files ──────────────────────────────────────────────
def read_meta(filename)
  path = File.join(METADATA, filename)
  return nil unless File.exist?(path)
  File.read(path).strip
end

# ── Main ────────────────────────────────────────────────────────────────────
puts "▸ Fetching app..."
apps = api_get("/apps?filter[bundleId]=#{BUNDLE_ID}&fields[apps]=appStoreVersions")
app_id = apps["data"][0]["id"]
puts "  App ID: #{app_id}"

puts "▸ Fetching live version..."
versions = api_get("/apps/#{app_id}/appStoreVersions?filter[appStoreState]=READY_FOR_SALE&fields[appStoreVersions]=versionString,appStoreState")
if versions["data"].empty?
  # Try other possible states
  versions = api_get("/apps/#{app_id}/appStoreVersions?fields[appStoreVersions]=versionString,appStoreState&limit=5")
  puts "  Available versions:"
  versions["data"].each { |v| puts "    #{v["attributes"]["versionString"]} — #{v["attributes"]["appStoreState"]}" }
end
version = versions["data"][0]
version_id = version["id"]
puts "  Version: #{version["attributes"]["versionString"]} (#{version["attributes"]["appStoreState"]})"

puts "▸ Fetching localizations..."
localizations = api_get("/appStoreVersions/#{version_id}/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale,description,keywords,promotionalText,whatsNew")
en_loc = localizations["data"].find { |l| l["attributes"]["locale"] == "en-US" }
abort "No en-US localization found!" unless en_loc
loc_id = en_loc["id"]
puts "  Localization ID: #{loc_id} (#{en_loc["attributes"]["locale"]})"

# Build update payload — only include fields we have files for
attrs = {}
desc = read_meta("description.txt")
attrs["description"] = desc if desc

keywords = read_meta("keywords.txt")
attrs["keywords"] = keywords if keywords

promo = read_meta("promotional_text.txt")
attrs["promotionalText"] = promo if promo

whats_new = read_meta("release_notes.txt")
attrs["whatsNew"] = whats_new if whats_new

if attrs.empty?
  puts "No metadata files found to update."
  exit 0
end

puts "▸ Updating #{attrs.keys.join(", ")}..."
result = api_patch("/appStoreVersionLocalizations/#{loc_id}", {
  data: {
    type: "appStoreVersionLocalizations",
    id: loc_id,
    attributes: attrs
  }
})

puts "✅ Metadata updated successfully!"
attrs.each_key { |k| puts "  ✓ #{k}" }
