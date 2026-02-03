require "./spec_helper"

describe Crinkle::Environment do
  describe "#globals" do
    it "allows setting and getting global variables" do
      env = Crinkle::Environment.new
      env.globals["app_name"] = Crinkle.value("MyApp")
      env.globals["build_id"] = Crinkle.value("abc123")

      env.globals["app_name"].should eq("MyApp")
      env.globals["build_id"].should eq("abc123")
    end

    it "makes globals accessible in templates" do
      env = Crinkle::Environment.new
      env.globals["app_name"] = Crinkle.value("MyApp")

      template = env.from_string("Welcome to {{ app_name }}!")
      output = template.render
      output.should eq("Welcome to MyApp!")
    end

    it "allows context to override globals" do
      env = Crinkle::Environment.new
      env.globals["name"] = Crinkle.value("Global")

      template = env.from_string("Hello {{ name }}!")
      output = template.render(name: "Local")
      output.should eq("Hello Local!")
    end

    it "falls back to globals when not in context" do
      env = Crinkle::Environment.new
      env.globals["app"] = Crinkle.value("MyApp")

      template = env.from_string("{{ app }} - {{ name }}")
      output = template.render(name: "User")
      output.should eq("MyApp - User")
    end
  end

  describe "#global" do
    it "returns the global value if present" do
      env = Crinkle::Environment.new
      env.globals["key"] = Crinkle.value("value")

      result = env.global("key")
      result.should eq("value")
    end

    it "returns Undefined for missing globals" do
      env = Crinkle::Environment.new

      result = env.global("missing")
      result.should be_a(Crinkle::Undefined)
    end
  end

  describe "#has_global?" do
    it "returns true for existing globals" do
      env = Crinkle::Environment.new
      env.globals["key"] = Crinkle.value("value")

      env.has_global?("key").should be_true
    end

    it "returns false for missing globals" do
      env = Crinkle::Environment.new

      env.has_global?("missing").should be_false
    end
  end

  describe "#new_child" do
    it "creates a child environment with parent reference" do
      parent = Crinkle::Environment.new
      child = parent.new_child

      child.parent.should eq(parent)
    end

    it "inherits filters from parent" do
      parent = Crinkle::Environment.new
      parent.register_filter("shout") do |value, _args, _kwargs, _ctx|
        value.to_s.upcase + "!"
      end

      child = parent.new_child
      template = child.from_string("{{ msg | shout }}")
      output = template.render(msg: "hello")
      output.should eq("HELLO!")
    end

    it "inherits tests from parent" do
      parent = Crinkle::Environment.new
      parent.register_test("loud") do |value, _args, _kwargs, _ctx|
        value.to_s == value.to_s.upcase
      end

      child = parent.new_child
      template = child.from_string("{% if msg is loud %}YES{% else %}NO{% endif %}")
      output = template.render(msg: "HELLO")
      output.should eq("YES")
    end

    it "inherits functions from parent" do
      parent = Crinkle::Environment.new
      parent.register_function("greet") do |args, _kwargs, _ctx|
        "Hello #{args.first}"
      end

      child = parent.new_child
      template = child.from_string("{{ greet(name) }}")
      output = template.render(name: "World")
      output.should eq("Hello World")
    end

    it "inherits template loader from parent" do
      parent = Crinkle::Environment.new
      parent.set_loader do |name|
        name == "base.j2" ? "Base content" : nil
      end

      child = parent.new_child
      template = child.get_template("base.j2")
      template.source.should eq("Base content")
    end

    it "inherits strict settings from parent" do
      parent = Crinkle::Environment.new(strict_undefined: false, strict_filters: false)
      child = parent.new_child

      child.strict_undefined?.should be_false
      child.strict_filters?.should be_false
    end

    it "allows child to override filters" do
      parent = Crinkle::Environment.new
      parent.register_filter("shout") do |value, _args, _kwargs, _ctx|
        value.to_s.upcase + "!"
      end

      child = parent.new_child
      child.register_filter("shout") do |value, _args, _kwargs, _ctx|
        value.to_s.upcase + "!!!"
      end

      template = child.from_string("{{ msg | shout }}")
      output = template.render(msg: "hello")
      output.should eq("HELLO!!!")
    end

    it "child filter override does not affect parent" do
      parent = Crinkle::Environment.new
      parent.register_filter("shout") do |value, _args, _kwargs, _ctx|
        value.to_s.upcase + "!"
      end

      child = parent.new_child
      child.register_filter("shout") do |value, _args, _kwargs, _ctx|
        value.to_s.upcase + "!!!"
      end

      template = parent.from_string("{{ msg | shout }}")
      output = template.render(msg: "hello")
      output.should eq("HELLO!")
    end
  end

  describe "global inheritance through parent chain" do
    it "child can access parent globals" do
      parent = Crinkle::Environment.new
      parent.globals["app_name"] = Crinkle.value("MyApp")

      child = parent.new_child

      template = child.from_string("Welcome to {{ app_name }}!")
      output = template.render
      output.should eq("Welcome to MyApp!")
    end

    it "child globals take precedence over parent globals" do
      parent = Crinkle::Environment.new
      parent.globals["app_name"] = Crinkle.value("ParentApp")

      child = parent.new_child
      child.globals["app_name"] = Crinkle.value("ChildApp")

      template = child.from_string("Welcome to {{ app_name }}!")
      output = template.render
      output.should eq("Welcome to ChildApp!")
    end

    it "child modification does not affect parent" do
      parent = Crinkle::Environment.new
      parent.globals["app_name"] = Crinkle.value("ParentApp")

      child = parent.new_child
      child.globals["app_name"] = Crinkle.value("ChildApp")

      parent.globals["app_name"].should eq("ParentApp")
    end

    it "supports multi-level inheritance" do
      grandparent = Crinkle::Environment.new
      grandparent.globals["level"] = Crinkle.value("grandparent")

      parent = grandparent.new_child
      child = parent.new_child

      template = child.from_string("Level: {{ level }}")
      output = template.render
      output.should eq("Level: grandparent")
    end

    it "each level can add its own globals" do
      grandparent = Crinkle::Environment.new
      grandparent.globals["gp_var"] = Crinkle.value("from grandparent")

      parent = grandparent.new_child
      parent.globals["p_var"] = Crinkle.value("from parent")

      child = parent.new_child
      child.globals["c_var"] = Crinkle.value("from child")

      template = child.from_string("{{ gp_var }}, {{ p_var }}, {{ c_var }}")
      output = template.render
      output.should eq("from grandparent, from parent, from child")
    end
  end

  describe "defined/undefined tests with globals" do
    it "defined test returns true for globals" do
      env = Crinkle::Environment.new
      env.globals["app_name"] = Crinkle.value("MyApp")

      template = env.from_string("{% if app_name is defined %}YES{% else %}NO{% endif %}")
      output = template.render
      output.should eq("YES")
    end

    it "undefined test returns false for globals" do
      env = Crinkle::Environment.new
      env.globals["app_name"] = Crinkle.value("MyApp")

      template = env.from_string("{% if app_name is undefined %}YES{% else %}NO{% endif %}")
      output = template.render
      output.should eq("NO")
    end

    it "defined test returns true for inherited globals" do
      parent = Crinkle::Environment.new
      parent.globals["app_name"] = Crinkle.value("MyApp")

      child = parent.new_child
      template = child.from_string("{% if app_name is defined %}YES{% else %}NO{% endif %}")
      output = template.render
      output.should eq("YES")
    end
  end

  describe "production usage pattern" do
    it "supports global/per-request context pattern" do
      # Global environment - shared across all requests
      global_env = Crinkle::Environment.new
      global_env.globals["app_name"] = Crinkle.value("MyApp")
      global_env.globals["build_id"] = Crinkle.value("abc123")
      global_env.set_loader { |_name| nil }

      # Simulate per-request handling
      request_env = global_env.new_child

      template = request_env.from_string("{{ app_name }} ({{ build_id }}) - Welcome {{ user }}!")
      output = template.render(user: "Alice")
      output.should eq("MyApp (abc123) - Welcome Alice!")

      # Another request with different context
      another_env = global_env.new_child

      template2 = another_env.from_string("{{ app_name }} - Hello {{ user }}!")
      output2 = template2.render(user: "Bob")
      output2.should eq("MyApp - Hello Bob!")

      # Global is unchanged
      global_env.globals["app_name"].should eq("MyApp")
    end

    it "per-request context does not pollute global environment" do
      global_env = Crinkle::Environment.new
      global_env.globals["app"] = Crinkle.value("App")

      # Request 1 adds a request-specific global
      request1 = global_env.new_child
      request1.globals["request_id"] = Crinkle.value("req-001")

      # Request 2 should not see request 1's globals
      request2 = global_env.new_child

      global_env.has_global?("request_id").should be_false
      request2.has_global?("request_id").should be_false
      request1.has_global?("request_id").should be_true
    end
  end

  describe "globals with include" do
    it "included templates can access globals" do
      env = Crinkle::Environment.new
      env.globals["site_name"] = Crinkle.value("MySite")
      env.set_loader do |name|
        name == "header.j2" ? "<header>{{ site_name }}</header>" : nil
      end

      template = env.from_string("{% include 'header.j2' %}<main>Content</main>")
      output = template.render
      output.should eq("<header>MySite</header><main>Content</main>")
    end

    it "included templates can access inherited globals" do
      parent = Crinkle::Environment.new
      parent.globals["brand"] = Crinkle.value("Acme")
      parent.set_loader do |name|
        name == "footer.j2" ? "<footer>{{ brand }} Inc.</footer>" : nil
      end

      child = parent.new_child
      template = child.from_string("<body>{% include 'footer.j2' %}</body>")
      output = template.render
      output.should eq("<body><footer>Acme Inc.</footer></body>")
    end

    it "include with context still has access to globals" do
      env = Crinkle::Environment.new
      env.globals["app"] = Crinkle.value("MyApp")
      env.set_loader do |name|
        name == "partial.j2" ? "{{ app }}: {{ local_var }}" : nil
      end

      template = env.from_string("{% set local_var = 'test' %}{% include 'partial.j2' with context %}")
      output = template.render
      output.should eq("MyApp: test")
    end
  end

  describe "globals with import" do
    it "imported macros can access globals" do
      env = Crinkle::Environment.new
      env.globals["prefix"] = Crinkle.value("[INFO]")
      env.set_loader do |name|
        name == "macros.j2" ? "{% macro log(msg) %}{{ prefix }} {{ msg }}{% endmacro %}" : nil
      end

      template = env.from_string("{% import 'macros.j2' as m %}{{ m.log('Hello') }}")
      output = template.render
      output.should eq("[INFO] Hello")
    end

    it "from-imported macros can access globals" do
      env = Crinkle::Environment.new
      env.globals["separator"] = Crinkle.value(" | ")
      env.set_loader do |name|
        name == "utils.j2" ? "{% macro join_items(items) %}{% for item in items %}{{ item }}{% if not loop.last %}{{ separator }}{% endif %}{% endfor %}{% endmacro %}" : nil
      end

      template = env.from_string("{% from 'utils.j2' import join_items %}{{ join_items(['a', 'b', 'c']) }}")
      output = template.render
      output.should eq("a | b | c")
    end
  end

  describe "globals with extends" do
    it "child template can access globals defined in parent env" do
      env = Crinkle::Environment.new
      env.globals["site_title"] = Crinkle.value("My Website")
      env.set_loader do |name|
        name == "base.j2" ? "<title>{{ site_title }}</title>{% block content %}{% endblock %}" : nil
      end

      template = env.from_string("{% extends 'base.j2' %}{% block content %}Page content{% endblock %}")
      output = template.render
      output.should eq("<title>My Website</title>Page content")
    end

    it "block override can access globals" do
      env = Crinkle::Environment.new
      env.globals["version"] = Crinkle.value("1.0.0")
      env.set_loader do |name|
        name == "layout.j2" ? "{% block footer %}Default{% endblock %}" : nil
      end

      template = env.from_string("{% extends 'layout.j2' %}{% block footer %}Version: {{ version }}{% endblock %}")
      output = template.render
      output.should eq("Version: 1.0.0")
    end

    it "super() works with globals" do
      env = Crinkle::Environment.new
      env.globals["app"] = Crinkle.value("MyApp")
      env.set_loader do |name|
        name == "parent.j2" ? "{% block header %}{{ app }}{% endblock %}" : nil
      end

      template = env.from_string("{% extends 'parent.j2' %}{% block header %}{{ super() }} - Extended{% endblock %}")
      output = template.render
      output.should eq("MyApp - Extended")
    end
  end

  describe "globals with macros" do
    it "macros can access globals" do
      env = Crinkle::Environment.new
      env.globals["currency"] = Crinkle.value("$")

      template = env.from_string("{% macro price(amount) %}{{ currency }}{{ amount }}{% endmacro %}{{ price(99) }}")
      output = template.render
      output.should eq("$99")
    end

    it "nested macro calls can access globals" do
      env = Crinkle::Environment.new
      env.globals["wrapper"] = Crinkle.value("**")

      template = env.from_string(<<-TEMPLATE
        {% macro bold(text) %}{{ wrapper }}{{ text }}{{ wrapper }}{% endmacro %}
        {% macro header(text) %}{{ bold(text) }}{% endmacro %}
        {{ header('Title') }}
        TEMPLATE
      )
      output = template.render.strip
      output.should eq("**Title**")
    end

    it "macro default values can reference globals" do
      env = Crinkle::Environment.new
      env.globals["default_name"] = Crinkle.value("Guest")

      template = env.from_string("{% macro greet(name=default_name) %}Hello {{ name }}{% endmacro %}{{ greet() }}")
      output = template.render
      output.should eq("Hello Guest")
    end

    it "call blocks can access globals" do
      env = Crinkle::Environment.new
      env.globals["tag"] = Crinkle.value("div")

      template = env.from_string(<<-TEMPLATE
        {% macro container() %}<{{ tag }}>{{ caller() }}</{{ tag }}>{% endmacro %}
        {% call container() %}Content{% endcall %}
        TEMPLATE
      )
      output = template.render.strip
      output.should eq("<div>Content</div>")
    end
  end

  describe "register_global" do
    it "registers global value and schema type" do
      env = Crinkle::Environment.new
      env.register_global("ctx", Crinkle.value("context"), "Context")

      env.globals["ctx"].to_s.should eq("context")
      Crinkle::Schema.registry.globals["ctx"].should eq("Context")
    end
  end

  describe "RenderContext globals access" do
    it "filters can access globals via context" do
      env = Crinkle::Environment.new
      env.globals["multiplier"] = Crinkle.value(2_i64)
      env.register_filter("multiply_by_global") do |value, _args, _kwargs, ctx|
        num = value.as(Int64)
        mult = ctx.global("multiplier").as(Int64)
        (num * mult).to_i64
      end

      template = env.from_string("{{ 5 | multiply_by_global }}")
      output = template.render
      output.should eq("10")
    end

    it "filters can check global existence via context" do
      env = Crinkle::Environment.new
      env.globals["prefix"] = Crinkle.value(">>")
      env.register_filter("maybe_prefix") do |value, _args, _kwargs, ctx|
        if ctx.has_global?("prefix")
          "#{ctx.global("prefix")}#{value}"
        else
          value.to_s
        end
      end

      template = env.from_string("{{ 'test' | maybe_prefix }}")
      output = template.render
      output.should eq(">>test")
    end

    it "filters can access inherited globals via context" do
      parent = Crinkle::Environment.new
      parent.globals["suffix"] = Crinkle.value("!")

      child = parent.new_child
      child.register_filter("add_suffix") do |value, _args, _kwargs, ctx|
        suffix = ctx.global("suffix")
        "#{value}#{suffix}"
      end

      template = child.from_string("{{ 'Hello' | add_suffix }}")
      output = template.render
      output.should eq("Hello!")
    end

    it "tests can access globals via context" do
      env = Crinkle::Environment.new
      env.globals["threshold"] = Crinkle.value(10_i64)
      env.register_test("above_threshold") do |value, _args, _kwargs, ctx|
        threshold = ctx.global("threshold").as(Int64)
        value.as(Int64) > threshold
      end

      template = env.from_string("{% if 15 is above_threshold %}YES{% else %}NO{% endif %}")
      output = template.render
      output.should eq("YES")
    end

    it "functions can access globals via context" do
      env = Crinkle::Environment.new
      env.globals["base_url"] = Crinkle.value("https://example.com")
      env.register_function("full_url") do |args, _kwargs, ctx|
        path = args.first.to_s
        base = ctx.global("base_url").to_s
        "#{base}#{path}"
      end

      template = env.from_string("{{ full_url('/page') }}")
      output = template.render
      output.should eq("https://example.com/page")
    end

    it "context returns Undefined for missing globals" do
      env = Crinkle::Environment.new
      env.register_filter("check_missing") do |_value, _args, _kwargs, ctx|
        result = ctx.global("nonexistent")
        result.is_a?(Crinkle::Undefined) ? "undefined" : "found"
      end

      template = env.from_string("{{ 'x' | check_missing }}")
      output = template.render
      output.should eq("undefined")
    end
  end
end
