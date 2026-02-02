require "./spec_helper"

describe Crinkle::Template do
  describe "#render" do
    it "renders a template with context" do
      env = Crinkle::Environment.new
      template = env.from_string("Hello {{ name }}!")
      context = {"name" => "World"} of String => Crinkle::Value
      output = template.render(context)
      output.should eq("Hello World!")
    end

    it "renders a template with named tuple syntax" do
      env = Crinkle::Environment.new
      template = env.from_string("Hello {{ name }}!")
      output = template.render(name: "Crystal")
      output.should eq("Hello Crystal!")
    end

    it "renders a template with empty context" do
      env = Crinkle::Environment.new
      template = env.from_string("Static content")
      output = template.render
      output.should eq("Static content")
    end

    it "preserves the environment reference" do
      env = Crinkle::Environment.new
      env.register_filter("shout") do |value, _args, _kwargs, _ctx|
        value.to_s.upcase + "!"
      end
      template = env.from_string("{{ msg | shout }}")
      context = {"msg" => "hello"} of String => Crinkle::Value
      output = template.render(context)
      output.should eq("HELLO!")
    end
  end

  describe "#name" do
    it "returns the template name" do
      env = Crinkle::Environment.new
      template = env.from_string("content", "my-template")
      template.name.should eq("my-template")
    end

    it "uses <string> as default name" do
      env = Crinkle::Environment.new
      template = env.from_string("content")
      template.name.should eq("<string>")
    end
  end

  describe "#source" do
    it "returns the template source" do
      env = Crinkle::Environment.new
      source = "Hello {{ name }}!"
      template = env.from_string(source)
      template.source.should eq(source)
    end
  end
end

describe Crinkle::Environment do
  describe "#from_string" do
    it "creates a template from a string" do
      env = Crinkle::Environment.new
      template = env.from_string("Hello {{ name }}!")
      template.should be_a(Crinkle::Template)
      template.source.should eq("Hello {{ name }}!")
    end

    it "accepts an optional name" do
      env = Crinkle::Environment.new
      template = env.from_string("content", "custom-name")
      template.name.should eq("custom-name")
    end
  end

  describe "#get_template" do
    it "loads a template from the loader" do
      env = Crinkle::Environment.new
      env.set_loader do |name|
        name == "greeting.j2" ? "Hello {{ name }}!" : nil
      end

      template = env.get_template("greeting.j2")
      template.name.should eq("greeting.j2")
      context = {"name" => "World"} of String => Crinkle::Value
      output = template.render(context)
      output.should eq("Hello World!")
    end

    it "raises TemplateNotFoundError when template not found" do
      env = Crinkle::Environment.new
      env.set_loader { |_name| nil }

      expect_raises(Crinkle::TemplateNotFoundError, "Template 'missing.j2' not found") do
        env.get_template("missing.j2")
      end
    end

    it "raises TemplateNotFoundError when no loader configured" do
      env = Crinkle::Environment.new

      expect_raises(Crinkle::TemplateNotFoundError, "Template 'any.j2' not found") do
        env.get_template("any.j2")
      end
    end

    it "loads different templates" do
      env = Crinkle::Environment.new
      env.set_loader { |name| "Content of #{name}" }

      t1 = env.get_template("first.j2")
      t2 = env.get_template("second.j2")

      t1.source.should eq("Content of first.j2")
      t2.source.should eq("Content of second.j2")
    end
  end

  describe "#render" do
    it "renders a template by name with context" do
      env = Crinkle::Environment.new
      env.set_loader do |name|
        name == "page.j2" ? "<h1>{{ title }}</h1>" : nil
      end

      context = {"title" => "Welcome"} of String => Crinkle::Value
      output = env.render("page.j2", context)
      output.should eq("<h1>Welcome</h1>")
    end

    it "renders a template by name with named arguments" do
      env = Crinkle::Environment.new
      env.set_loader do |name|
        name == "page.j2" ? "<h1>{{ title }}</h1>" : nil
      end

      output = env.render("page.j2", title: "Welcome")
      output.should eq("<h1>Welcome</h1>")
    end

    it "renders a template with empty context" do
      env = Crinkle::Environment.new
      env.set_loader { |_name| "Static page" }

      output = env.render("static.j2")
      output.should eq("Static page")
    end
  end
end

describe Crinkle::TemplateNotFoundError do
  it "stores the template name" do
    error = Crinkle::TemplateNotFoundError.new("missing.j2")
    error.template_name.should eq("missing.j2")
  end

  it "has a descriptive message" do
    error = Crinkle::TemplateNotFoundError.new("missing.j2")
    error.message.should eq("Template 'missing.j2' not found")
  end

  it "allows custom message" do
    error = Crinkle::TemplateNotFoundError.new("missing.j2", message: "Custom error")
    error.message.should eq("Custom error")
  end

  it "stores the loader name" do
    error = Crinkle::TemplateNotFoundError.new("missing.j2", "FileLoader")
    error.loader.should eq("FileLoader")
  end
end
