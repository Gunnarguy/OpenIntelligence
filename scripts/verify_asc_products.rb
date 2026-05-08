#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spaceship'
require 'json'
require_relative 'app_store_connect_env'

# Authenticate with App Store Connect API
api_key = Spaceship::ConnectAPI::Token.create(
  key_id: AppStoreConnectEnv.required_value('APP_STORE_CONNECT_KEY_ID', 'APP_STORE_CONNECT_API_KEY_ID', 'ASC_KEY_ID'),
  issuer_id: AppStoreConnectEnv.required_value('APP_STORE_CONNECT_ISSUER', 'APP_STORE_CONNECT_ISSUER_ID', 'ASC_ISSUER_ID'),
  filepath: AppStoreConnectEnv.required_path('APP_STORE_CONNECT_PRIVATE_KEY_PATH', 'APP_STORE_CONNECT_API_KEY_PATH', 'ASC_KEY_PATH')
)
Spaceship::ConnectAPI.token = api_key

# Find the app
BUNDLE_ID = 'com.hostetler.OpenIntelligence'
apps = Spaceship::ConnectAPI::App.all
app = apps.find { |a| a.bundle_id == BUNDLE_ID }

if app.nil?
  puts "❌ App not found with bundle ID: #{BUNDLE_ID}"
  puts 'Available apps:'
  apps.each { |a| puts "  - #{a.bundle_id}: #{a.name}" }
  exit 1
end

puts "✅ Found app: #{app.name} (#{app.bundle_id})"
puts ''

# Get in-app purchases using direct API call
response = Spaceship::ConnectAPI.get("apps/#{app.id}/inAppPurchasesV2")
iaps = response.all_pages_each.to_a

puts "📦 In-App Purchases from App Store Connect (#{iaps.count}):"
server_products = {}
iaps.each do |iap|
  product_id = iap.product_id
  iap_type = iap.in_app_purchase_type
  state = iap.state
  server_products[product_id] = { type: iap_type, state: state }
  status = state == 'READY_TO_SUBMIT' || state == 'APPROVED' ? '✅' : '⚠️'
  puts "  #{status} #{product_id} | #{iap_type} | #{state}"
end

puts ''

# Load local subscriptions.json
local_file = File.join(__dir__, '..', 'fastlane', 'subscriptions.json')
if File.exist?(local_file)
  local_config = JSON.parse(File.read(local_file))
  local_products = local_config['products']

  puts "📋 Local subscriptions.json products (#{local_products.count}):"
  local_products.each do |p|
    product_id = p['product_id']
    exists = server_products.key?(product_id)
    status = exists ? '✅' : '❌'
    server_state = exists ? server_products[product_id][:state] : 'NOT FOUND'
    puts "  #{status} #{product_id} | #{p['type']} | Server: #{server_state}"
  end

  puts ''

  # Summary
  missing = local_products.map { |p| p['product_id'] }.reject { |id| server_products.key?(id) }
  extra = server_products.keys.reject { |id| local_products.any? { |p| p['product_id'] == id } }

  if missing.empty? && extra.empty?
    puts '✅ All products match between local config and App Store Connect!'
  else
    puts '⚠️  Mismatch detected:'
    puts "  Missing on server: #{missing.join(', ')}" unless missing.empty?
    puts "  Extra on server: #{extra.join(', ')}" unless extra.empty?
  end
else
  puts "⚠️  Local subscriptions.json not found at #{local_file}"
end
