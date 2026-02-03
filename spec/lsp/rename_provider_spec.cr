require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::RenameProvider do
    it "prepares rename for variables" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::RenameProvider.new(inference, documents)

      template = "{% set name = 'Alice' %}{{ name }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Position on "name" in output
      result = provider.prepare_rename(uri, template, Crinkle::LSP::Position.new(0, 28))

      result.should_not be_nil
      if res = result
        res.placeholder.should eq "name"
      end
    end

    it "rejects reserved names" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::RenameProvider.new(inference, documents)

      template = "{% set x = 1 %}{{ x }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Try to rename to reserved word "for"
      edit = provider.rename(uri, template, Crinkle::LSP::Position.new(0, 18), "for")

      edit.should be_nil
    end

    it "renames variables across file" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::RenameProvider.new(inference, documents)

      template = "{% set x = 1 %}{{ x }} {{ x }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      # Rename x to y
      edit = provider.rename(uri, template, Crinkle::LSP::Position.new(0, 18), "y")

      edit.should_not be_nil
      if e = edit
        changes = e.changes
        changes.should_not be_nil
        if c = changes
          c[uri]?.should_not be_nil
          c[uri].size.should eq 3 # definition + 2 usages
        end
      end
    end

    it "renames macros across unopened files using workspace index" do
      tmp_dir = File.join(Dir.tempdir, "crinkle-lsp-#{Time.utc.to_unix_ms}-#{Process.pid}")
      templates_dir = File.join(tmp_dir, "templates")
      FileUtils.mkdir_p(templates_dir)

      begin
        macro_path = File.join(templates_dir, "macros.html.j2")
        page_path = File.join(templates_dir, "page.html.j2")
        File.write(macro_path, "{% macro button() %}ok{% endmacro %}")
        File.write(page_path, "{{ button() }}")

        config = Crinkle::LSP::Config.new(template_paths: ["templates"])
        inference = Crinkle::LSP::InferenceEngine.new(config, tmp_dir)
        documents = Crinkle::LSP::DocumentStore.new
        index = Crinkle::LSP::WorkspaceIndex.new(config, tmp_dir)
        index.rebuild

        page_uri = "file://#{page_path}"
        documents.open(page_uri, "jinja2", File.read(page_path), 1)

        provider = Crinkle::LSP::RenameProvider.new(inference, documents, index, tmp_dir)

        edit = provider.rename(page_uri, File.read(page_path), Crinkle::LSP::Position.new(0, 3), "primary_button")

        edit.should_not be_nil
        if e = edit
          changes = e.changes
          changes.should_not be_nil
          if c = changes
            c.keys.should contain page_uri
            c.keys.should contain "file://#{macro_path}"
          end
        end
      ensure
        FileUtils.rm_r(tmp_dir) if Dir.exists?(tmp_dir)
      end
    end
  end
end
