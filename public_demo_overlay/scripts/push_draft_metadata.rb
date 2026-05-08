#!/usr/bin/env ruby
require_relative "app_store_connect_env"

require "jwt"
require "net/http"
require "json"
require "uri"

key_path = AppStoreConnectEnv.required_app_store_connect_key_path
key_id = AppStoreConnectEnv.required_app_store_connect_key_id
issuer_id = AppStoreConnectEnv.required_app_store_connect_issuer

private_key = OpenSSL::PKey::EC.new(File.read(key_path))
now = Time.now.to_i
payload = { iss: issuer_id, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" }
token = JWT.encode(payload, private_key, "ES256", { kid: key_id, typ: "JWT" })

loc_id = "b735551d-848c-4f2f-94ea-6c091352052e"

# Read local metadata files
base = File.expand_path("fastlane/metadata/en-US", __dir__ + "/..")
description = File.read(File.join(base, "description.txt")).strip
keywords = File.read(File.join(base, "keywords.txt")).strip
release_notes = File.read(File.join(base, "release_notes.txt")).strip

puts "Description: #{description.length} chars"
puts "Keywords: #{keywords.length} chars"
puts "Release notes: #{release_notes.length} chars"
puts ""

uri = URI("https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/#{loc_id}")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

body = {
  data: {
    type: "appStoreVersionLocalizations",
    id: loc_id,
    attributes: {
      description: description,
      keywords: keywords,
      whatsNew: release_notes
    }
  }
}.to_json

req = Net::HTTP::Patch.new(uri)
req["Authorization"] = "Bearer #{token}"
req["Content-Type"] = "application/json"
req.body = body

res = http.request(req)
puts "Status: #{res.code}"

parsed = JSON.parse(res.body)
if res.code == "200"
  attrs = parsed["data"]["attributes"]
  puts "SUCCESS — Updated localization #{loc_id}"
  puts "Description length: #{attrs['description']&.length}"
  puts "Keywords: #{attrs['keywords']}"
  puts "WhatsNew length: #{attrs['whatsNew']&.length}"
else
  puts "FAILED:"
  puts JSON.pretty_generate(parsed)
end