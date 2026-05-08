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

base = File.expand_path("fastlane/metadata/en-US", __dir__ + "/..")
promo_text = File.read(File.join(base, "promotional_text.txt")).strip

puts "Promotional text (#{promo_text.length} chars): #{promo_text}"

uri = URI("https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/#{loc_id}")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

body = {
  data: {
    type: "appStoreVersionLocalizations",
    id: loc_id,
    attributes: {
      promotionalText: promo_text
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
  puts "SUCCESS — Promotional text pushed to v2.1.1 draft"
else
  puts "FAILED:"
  puts JSON.pretty_generate(parsed)
end
