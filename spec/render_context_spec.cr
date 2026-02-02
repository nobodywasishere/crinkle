require "./spec_helper"

describe "RenderContext" do
  describe "filter access to context" do
    it "allows filters to access context variables" do
      env = Crinkle::Environment.new

      env.register_filter("greet_user") do |value, _args, _kwargs, ctx|
        user_name = ctx["user_name"]
        if user_name.is_a?(String)
          "#{value} #{user_name}"
        else
          "#{value} Guest"
        end
      end

      context = Hash(String, Crinkle::Value).new
      context["user_name"] = "Alice"
      context["greeting"] = "Hello"

      source = "{{ greeting | greet_user }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens, env)
      template = parser.parse

      renderer = Crinkle::Renderer.new(env)
      output = renderer.render(template, context)
      output.should eq("Hello Alice")
    end

    it "returns Undefined for missing context variables" do
      env = Crinkle::Environment.new

      env.register_filter("check_missing") do |value, _args, _kwargs, ctx|
        missing = ctx["nonexistent"]
        if missing.is_a?(Crinkle::Undefined)
          "#{value} - missing"
        else
          "#{value} - found"
        end
      end

      context = Hash(String, Crinkle::Value).new
      context["msg"] = "Status"

      source = "{{ msg | check_missing }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens, env)
      template = parser.parse

      renderer = Crinkle::Renderer.new(env)
      output = renderer.render(template, context)
      output.should eq("Status - missing")
    end
  end

  describe "function access to context" do
    it "allows functions to access context variables" do
      env = Crinkle::Environment.new

      env.register_function("get_config") do |args, _kwargs, ctx|
        key = args.first?.to_s
        config = ctx["config"]
        if config.is_a?(Hash(String, Crinkle::Value))
          config[key]? || "default"
        else
          "no config"
        end
      end

      config = Hash(String, Crinkle::Value).new
      config["theme"] = "dark"
      config["lang"] = "en"

      context = Hash(String, Crinkle::Value).new
      context["config"] = config

      source = "Theme: {{ get_config('theme') }}, Lang: {{ get_config('lang') }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens, env)
      template = parser.parse

      renderer = Crinkle::Renderer.new(env)
      output = renderer.render(template, context)
      output.should eq("Theme: dark, Lang: en")
    end
  end

  describe "test access to context" do
    it "allows tests to access context variables" do
      env = Crinkle::Environment.new

      env.register_test("in_allowed_list") do |value, _args, _kwargs, ctx|
        allowed = ctx["allowed_items"]
        if allowed.is_a?(Array(Crinkle::Value))
          allowed.includes?(value)
        else
          false
        end
      end

      context = Hash(String, Crinkle::Value).new
      context["allowed_items"] = ["apple", "banana", "cherry"] of Crinkle::Value
      context["item1"] = "banana"
      context["item2"] = "grape"

      source = "{% if item1 is in_allowed_list %}yes{% else %}no{% endif %}-{% if item2 is in_allowed_list %}yes{% else %}no{% endif %}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens, env)
      template = parser.parse

      renderer = Crinkle::Renderer.new(env)
      output = renderer.render(template, context)
      output.should eq("yes-no")
    end
  end

  describe "RenderContext struct" do
    it "provides access to environment" do
      env = Crinkle::Environment.new

      env.register_filter("env_has_filter") do |value, args, _kwargs, ctx|
        filter_name = args.first?.to_s
        if ctx.env.filters.has_key?(filter_name)
          "#{value} has filter"
        else
          "#{value} no filter"
        end
      end

      context = Hash(String, Crinkle::Value).new
      context["msg"] = "upper"

      source = "{{ msg | env_has_filter('upper') }}"
      lexer = Crinkle::Lexer.new(source)
      tokens = lexer.lex_all
      parser = Crinkle::Parser.new(tokens, env)
      template = parser.parse

      renderer = Crinkle::Renderer.new(env)
      output = renderer.render(template, context)
      output.should eq("upper has filter")
    end
  end
end
