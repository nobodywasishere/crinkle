module Crinkle::Std::Tests
  module Strings
    def self.register(env : Environment) : Nil
      env.register_test("lower") do |value, _args, _kwargs|
        str = value.to_s
        !str.empty? && str == str.downcase
      end

      env.register_test("upper") do |value, _args, _kwargs|
        str = value.to_s
        !str.empty? && str == str.upcase
      end

      env.register_test("startswith") do |value, args, _kwargs|
        prefix = args.first?.to_s
        value.to_s.starts_with?(prefix)
      end

      env.register_test("endswith") do |value, args, _kwargs|
        suffix = args.first?.to_s
        value.to_s.ends_with?(suffix)
      end
    end
  end
end
