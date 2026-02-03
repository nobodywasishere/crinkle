require "../spec_helper"

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

    it "renames only the variable in the correct scope" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::RenameProvider.new(inference, documents)

      template = "{% set x = 1 %}{{ x }}{% for x in xs %}{{ x }}{% endfor %}{{ x }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      first_output = template.index!("{{ x }}")
      position = Crinkle::LSP::Position.new(0, first_output + 3)

      edit = provider.rename(uri, template, position, "y")

      edit.should_not be_nil
      if e = edit
        changes = e.changes
        changes.should_not be_nil
        changes = changes.as(Hash(String, Array(Crinkle::LSP::TextEdit)))
        changes[uri].size.should eq 3
      end
    end

    it "renames only context references when no declaration exists" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::RenameProvider.new(inference, documents)

      template = "{{ user.name }} {{ user }} {% set user = 1 %}{{ user }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      first_user = template.index!("user")
      position = Crinkle::LSP::Position.new(0, first_user)

      edit = provider.rename(uri, template, position, "account")

      edit.should_not be_nil
      if e = edit
        changes = e.changes
        changes.should_not be_nil
        changes = changes.as(Hash(String, Array(Crinkle::LSP::TextEdit)))
        changes[uri].size.should eq 2
      end
    end

    it "renames only the imported macro reference" do
      tmp_dir = File.join(Dir.tempdir, "crinkle-lsp-#{Time.utc.to_unix_ms}-#{Process.pid}")
      templates_dir = File.join(tmp_dir, "templates")
      FileUtils.mkdir_p(templates_dir)

      begin
        macro_path = File.join(templates_dir, "macros.html.j2")
        page_path = File.join(templates_dir, "page.html.j2")
        File.write(macro_path, "{% macro button() %}ok{% endmacro %}")
        File.write(page_path, "{% macro button() %}local{% endmacro %}{% from \"macros.html.j2\" import button %}{{ button() }}{{ button() }}")

        config = Crinkle::LSP::Config.new(template_paths: ["templates"])
        inference = Crinkle::LSP::InferenceEngine.new(config, tmp_dir)
        documents = Crinkle::LSP::DocumentStore.new
        index = Crinkle::LSP::WorkspaceIndex.new(config, tmp_dir)
        index.rebuild

        page_uri = "file://#{page_path}"
        documents.open(page_uri, "jinja2", File.read(page_path), 1)

        provider = Crinkle::LSP::RenameProvider.new(inference, documents, index, tmp_dir)

        content = File.read(page_path)
        import_offset = content.index!("import button") + "import ".size
        edit = provider.rename(page_uri, content, Crinkle::LSP::Position.new(0, import_offset), "primary_button")

        edit.should_not be_nil
        if e = edit
          changes = e.changes
          changes.should_not be_nil
          changes = changes.as(Hash(String, Array(Crinkle::LSP::TextEdit)))
          changes.keys.should contain page_uri
          changes.keys.should contain "file://#{macro_path}"
        end
      ensure
        FileUtils.rm_r(tmp_dir) if Dir.exists?(tmp_dir)
      end
    end

    it "renames blocks only in the same extends chain" do
      tmp_dir = File.join(Dir.tempdir, "crinkle-lsp-#{Time.utc.to_unix_ms}-#{Process.pid}")
      templates_dir = File.join(tmp_dir, "templates")
      FileUtils.mkdir_p(templates_dir)

      begin
        base_path = File.join(templates_dir, "base.html.j2")
        child_path = File.join(templates_dir, "child.html.j2")
        grand_path = File.join(templates_dir, "grand.html.j2")
        other_path = File.join(templates_dir, "other.html.j2")

        File.write(base_path, "{% block header %}base{% endblock %}")
        File.write(child_path, "{% extends \"base.html.j2\" %}{% block header %}child{% endblock %}")
        File.write(grand_path, "{% extends \"child.html.j2\" %}{% block header %}grand{% endblock %}")
        File.write(other_path, "{% block header %}other{% endblock %}")

        config = Crinkle::LSP::Config.new(template_paths: ["templates"])
        inference = Crinkle::LSP::InferenceEngine.new(config, tmp_dir)
        documents = Crinkle::LSP::DocumentStore.new
        index = Crinkle::LSP::WorkspaceIndex.new(config, tmp_dir)
        index.rebuild

        child_uri = "file://#{child_path}"
        content = File.read(child_path)
        documents.open(child_uri, "jinja2", content, 1)

        provider = Crinkle::LSP::RenameProvider.new(inference, documents, index, tmp_dir)

        block_offset = content.index!("header")
        edit = provider.rename(child_uri, content, Crinkle::LSP::Position.new(0, block_offset), "title")

        edit.should_not be_nil
        if e = edit
          changes = e.changes
          changes.should_not be_nil
          changes = changes.as(Hash(String, Array(Crinkle::LSP::TextEdit)))
          changes.keys.should contain "file://#{base_path}"
          changes.keys.should contain "file://#{child_path}"
          changes.keys.should contain "file://#{grand_path}"
          changes.keys.should_not contain "file://#{other_path}"
        end
      ensure
        FileUtils.rm_r(tmp_dir) if Dir.exists?(tmp_dir)
      end
    end

    it "does not allow renaming filters" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      documents = Crinkle::LSP::DocumentStore.new
      provider = Crinkle::LSP::RenameProvider.new(inference, documents)

      template = "{{ name|lower }}"
      uri = "file:///test.j2"
      documents.open(uri, "jinja2", template, 1)
      inference.analyze(uri, template)

      offset = template.index!("lower")
      result = provider.prepare_rename(uri, template, Crinkle::LSP::Position.new(0, offset))

      result.should be_nil
    end
  end
end
