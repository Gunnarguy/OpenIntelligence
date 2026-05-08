# frozen_string_literal: true

module AppStoreConnectEnv
  module_function

  def repo_root
    @repo_root ||= File.expand_path("..", __dir__)
  end

  def load_local_env!
    env_path = File.join(repo_root, ".env")
    return unless File.file?(env_path)

    File.foreach(env_path) do |line|
      entry = parse_env_line(line)
      next unless entry

      key, value = entry
      next if ENV.key?(key) && !ENV[key].to_s.empty?

      ENV[key] = value
    end
  end

  def value(*names)
    names.each do |name|
      current = ENV[name]
      return current unless current.nil? || current.empty?
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
end

AppStoreConnectEnv.load_local_env!