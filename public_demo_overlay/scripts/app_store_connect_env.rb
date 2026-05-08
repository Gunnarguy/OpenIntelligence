# frozen_string_literal: true

module AppStoreConnectEnv
  module_function

  def repo_root
    @repo_root ||= File.expand_path("..", __dir__)
  end

  def keys_dir
    File.join(repo_root, "fastlane", "keys")
  end

  def load_local_env!
    env_path = File.join(repo_root, ".env")
    return unless File.file?(env_path)

    File.foreach(env_path) do |line|
      entry = parse_env_line(line)
      next unless entry

      key, value = entry
      ENV[key] = value
    end
  end

  def value(*names)
    names.each do |name|
      current = ENV[name]
      next if current.nil? || current.empty? || placeholder_value?(current)

      return current
    end

    nil
  end

  def required_value(*names)
    value(*names) || abort("Missing required environment variable. Set one of: #{names.join(", ")} in your shell or repo .env file.")
  end

  def path_value(*names)
    current = value(*names)
    return nil if current.nil? || current.empty?

    File.expand_path(current, repo_root)
  end

  def required_path(*names)
    File.expand_path(required_value(*names), repo_root)
  end

  def app_store_connect_issuer
    value("APP_STORE_CONNECT_ISSUER", "APP_STORE_CONNECT_ISSUER_ID", "ASC_ISSUER_ID")
  end

  def required_app_store_connect_issuer
    app_store_connect_issuer || abort("Missing App Store Connect issuer ID. Set APP_STORE_CONNECT_ISSUER in your shell or repo .env file.")
  end

  def app_store_connect_key_path
    configured = path_value("APP_STORE_CONNECT_PRIVATE_KEY_PATH", "APP_STORE_CONNECT_API_KEY_PATH", "ASC_KEY_PATH")
    return configured unless configured.nil? || configured.empty?

    auto_discovered_key_path
  end

  def required_app_store_connect_key_path
    app_store_connect_key_path || abort("Missing App Store Connect key file. Put AuthKey_<KEY_ID>.p8 in fastlane/keys/ or set APP_STORE_CONNECT_PRIVATE_KEY_PATH in your shell or repo .env file.")
  end

  def app_store_connect_key_id
    value("APP_STORE_CONNECT_KEY_ID", "APP_STORE_CONNECT_API_KEY_ID", "ASC_KEY_ID") || key_id_from_path(app_store_connect_key_path)
  end

  def required_app_store_connect_key_id
    app_store_connect_key_id || abort("Missing App Store Connect key ID. Set APP_STORE_CONNECT_KEY_ID in your shell or repo .env file, or use the default AuthKey_<KEY_ID>.p8 filename in fastlane/keys/.")
  end

  def parse_env_line(line)
    stripped = line.strip
    return if stripped.empty? || stripped.start_with?("#")

    stripped = stripped.sub(/\Aexport\s+/, "")
    key, raw_value = stripped.split("=", 2)
    return if key.nil? || raw_value.nil?

    [key.strip, unquote(raw_value.strip)]
  end

  def unquote(value)
    if (value.start_with?("\"") && value.end_with?("\"")) || (value.start_with?("'") && value.end_with?("'"))
      value[1...-1]
    else
      value
    end
  end

  def placeholder_value?(value)
    value.include?("YOUR_") || value.include?("<KEY_ID>")
  end

  def auto_discovered_key_path
    exact_match = File.join(keys_dir, "AuthKey.p8")
    return exact_match if File.file?(exact_match)

    matches = Dir[File.join(keys_dir, "AuthKey*.p8")].sort.select { |path| File.file?(path) }
    return matches.first if matches.length == 1

    nil
  end

  def key_id_from_path(path)
    return nil if path.nil? || path.empty?

    basename = File.basename(path)
    match = basename.match(/\AAuthKey[_-]([^.]+)\.p8\z/)
    match && match[1]
  end
end

AppStoreConnectEnv.load_local_env!