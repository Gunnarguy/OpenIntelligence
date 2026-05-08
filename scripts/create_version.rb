#!/usr/bin/env ruby
require_relative "app_store_connect_env"

require "jwt"
require "net/http"
require "json"
require "uri"

key_path = AppStoreConnectEnv.required_path("APP_STORE_CONNECT_PRIVATE_KEY_PATH", "APP_STORE_CONNECT_API_KEY_PATH", "ASC_KEY_PATH")
key_id = AppStoreConnectEnv.required_value("APP_STORE_CONNECT_KEY_ID", "APP_STORE_CONNECT_API_KEY_ID", "ASC_KEY_ID")
issuer_id = AppStoreConnectEnv.required_value("APP_STORE_CONNECT_ISSUER", "APP_STORE_CONNECT_ISSUER_ID", "ASC_ISSUER_ID")
app_id = "6756559175"

private_key = OpenSSL::PKey::EC.new(File.read(key_path))
now = Time.now.to_i
payload = { iss: issuer_id, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" }
token = JWT.encode(payload, private_key, "ES256", { kid: key_id, typ: "JWT" })

# Create new version 2.1.1
uri = URI("https://api.appstoreconnect.apple.com/v1/appStoreVersions")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

body = {
  data: {
    type: "appStoreVersions",
    attributes: {
      platform: "IOS",
      versionString: "2.1.1"
    },
    relationships: {
      app: {
        data: { type: "apps", id: app_id }
      }
    }
  }
}.to_json

req = Net::HTTP::Post.new(uri)
req["Authorization"] = "Bearer #{token}"
req["Content-Type"] = "application/json"
req.body = body

res = http.request(req)
puts "Status: #{res.code}"
parsed = JSON.parse(res.body)
puts JSON.pretty_generate(parsed)

# Save the version ID for next step
if res.code == "201"
  version_id = parsed["data"]["id"]
  puts "\n=== VERSION CREATED ==="
  puts "Version ID: #{version_id}"

  # Get the localization ID for this new version
  loc_uri = URI("https://api.appstoreconnect.apple.com/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations")
  loc_req = Net::HTTP::Get.new(loc_uri)
  loc_req["Authorization"] = "Bearer #{token}"
  loc_res = http.request(loc_req)
  loc_parsed = JSON.parse(loc_res.body)
  puts "\nLocalizations:"
  puts JSON.pretty_generate(loc_parsed)
end
