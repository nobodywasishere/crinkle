module Crinkle::Std::Tests
  module Strings
    def self.register(env : Environment) : Nil
      env.register_test("lower") do |value, _args, _kwargs, _ctx|
        str = value.to_s
        !str.empty? && str == str.downcase
      end

      env.register_test("upper") do |value, _args, _kwargs, _ctx|
        str = value.to_s
        !str.empty? && str == str.upcase
      end

      env.register_test("startswith") do |value, args, _kwargs, _ctx|
        prefix = args.first?.to_s
        value.to_s.starts_with?(prefix)
      end

      env.register_test("endswith") do |value, args, _kwargs, _ctx|
        suffix = args.first?.to_s
        value.to_s.ends_with?(suffix)
      end
    end
  end
end
