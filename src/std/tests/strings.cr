module Crinkle::Std::Tests
  module Strings
    Crinkle.define_test :lower,
      params: {value: String},
      doc: "Check if string is lowercase" do |value|
      str = value.to_s
      !str.empty? && str == str.downcase
    end

    Crinkle.define_test :upper,
      params: {value: String},
      doc: "Check if string is uppercase" do |value|
      str = value.to_s
      !str.empty? && str == str.upcase
    end

    Crinkle.define_test :startswith,
      params: {value: String, prefix: String},
      doc: "Check if string starts with prefix" do |value, prefix|
      prefix = prefix.to_s
      value.to_s.starts_with?(prefix)
    end

    Crinkle.define_test :endswith,
      params: {value: String, suffix: String},
      doc: "Check if string ends with suffix" do |value, suffix|
      suffix = suffix.to_s
      value.to_s.ends_with?(suffix)
    end

    def self.register(env : Environment) : Nil
      register_test_lower(env)
      register_test_upper(env)
      register_test_startswith(env)
      register_test_endswith(env)
    end
  end
end
