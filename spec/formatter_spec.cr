require "./spec_helper"
require "../src/jinja"

describe Jinja::Formatter do
  describe "formatting" do
    Dir.glob("fixtures/templates/*.j2").each do |path|
      name = File.basename(path, ".j2")

      it "formats #{name}" do
        source = File.read(path)
        formatter = Jinja::Formatter.new(source)
        output = formatter.format

        assert_text_snapshot("fixtures/formatter_output/#{name}.j2", output)
        assert_diagnostics_snapshot("fixtures/formatter_diagnostics/#{name}.json", formatter.diagnostics)
      end
    end
  end

  describe "idempotency" do
    # Test that formatting twice produces the same result
    Dir.glob("fixtures/templates/*.j2").each do |path|
      name = File.basename(path, ".j2")

      it "is idempotent for #{name}" do
        source = File.read(path)
        formatter1 = Jinja::Formatter.new(source)
        output1 = formatter1.format

        formatter2 = Jinja::Formatter.new(output1)
        output2 = formatter2.format

        output1.should eq(output2)
      end
    end
  end

  describe "options" do
    it "respects space_inside_braces option" do
      source = "{{ name }}"

      with_spaces = Jinja::Formatter.new(source, Jinja::Formatter::Options.new(space_inside_braces: true))
      with_spaces.format.strip.should eq("{{ name }}")

      without_spaces = Jinja::Formatter.new(source, Jinja::Formatter::Options.new(space_inside_braces: false))
      without_spaces.format.strip.should eq("{{name}}")
    end

    it "respects space_around_operators option" do
      source = "{{ a + b }}"

      with_spaces = Jinja::Formatter.new(source, Jinja::Formatter::Options.new(space_around_operators: true))
      with_spaces.format.strip.should eq("{{ a + b }}")

      without_spaces = Jinja::Formatter.new(source, Jinja::Formatter::Options.new(space_around_operators: false))
      without_spaces.format.strip.should eq("{{ a+b }}")
    end
  end

  describe "comments" do
    it "formats comments with proper spacing" do
      source = "{#comment#}"
      formatter = Jinja::Formatter.new(source)
      formatter.format.strip.should eq("{# comment #}")
    end

    it "preserves multiline comment content" do
      source = "{# line1\nline2 #}"
      formatter = Jinja::Formatter.new(source)
      output = formatter.format.strip
      output.should eq("{#\n  line1\n  line2\n#}")
    end
  end
end
