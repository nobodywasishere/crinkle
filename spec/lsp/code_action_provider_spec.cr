require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::CodeActionProvider do
    it "extracts suggestion from 'Did you mean' message" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CodeActionProvider.new(inference)

      diagnostic = Crinkle::LSP::Diagnostic.new(
        range: Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 5),
          Crinkle::LSP::Position.new(0, 10)
        ),
        message: "Unknown property 'emial'. Did you mean 'email'?",
        code: "Inference/PossibleTypo"
      )

      context = Crinkle::LSP::CodeActionContext.new(diagnostics: [diagnostic])
      actions = provider.code_actions("file:///test.j2", diagnostic.range, context)

      actions.size.should eq 1
      actions[0].title.should eq "Change to 'email'"
    end

    it "returns empty for diagnostics without fixes" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CodeActionProvider.new(inference)

      diagnostic = Crinkle::LSP::Diagnostic.new(
        range: Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 0),
          Crinkle::LSP::Position.new(0, 10)
        ),
        message: "Some random error"
      )

      context = Crinkle::LSP::CodeActionContext.new(diagnostics: [diagnostic])
      actions = provider.code_actions("file:///test.j2", diagnostic.range, context)

      actions.should be_empty
    end

    it "suggests auto-import for unknown macros" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CodeActionProvider.new(inference, "/project")

      macro_template = %({% macro button(text) %}{{ text }}{% endmacro %})
      macro_uri = "file:///project/templates/macros.html.j2"
      inference.analyze(macro_uri, macro_template)

      template = %({{ button("Click") }})
      uri = "file:///project/templates/page.html.j2"

      diagnostic = Crinkle::LSP::Diagnostic.new(
        range: Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 3),
          Crinkle::LSP::Position.new(0, 9)
        ),
        message: "Unknown function 'button'.",
        code: "Lint/UnknownFunction"
      )

      context = Crinkle::LSP::CodeActionContext.new(diagnostics: [diagnostic])
      actions = provider.code_actions(uri, diagnostic.range, context, template)

      actions.size.should eq 1
      actions[0].title.should eq "Import 'button' from \"templates/macros.html.j2\""
    end

    it "suggests auto-imports from workspace index" do
      tmp_dir = File.join(Dir.tempdir, "crinkle-lsp-#{Time.utc.to_unix_ms}-#{Process.pid}")
      templates_dir = File.join(tmp_dir, "templates")
      FileUtils.mkdir_p(templates_dir)

      begin
        macro_path = File.join(templates_dir, "macros.html.j2")
        File.write(macro_path, "{% macro button(text) %}{{ text }}{% endmacro %}")

        config = Crinkle::LSP::Config.new(template_paths: ["templates"])
        inference = Crinkle::LSP::InferenceEngine.new(config)
        index = Crinkle::LSP::WorkspaceIndex.new(config, tmp_dir)
        index.rebuild

        provider = Crinkle::LSP::CodeActionProvider.new(inference, tmp_dir, index)

        template = %({{ button("Click") }})
        uri = "file://#{File.join(templates_dir, "page.html.j2")}"

        diagnostic = Crinkle::LSP::Diagnostic.new(
          range: Crinkle::LSP::Range.new(
            Crinkle::LSP::Position.new(0, 3),
            Crinkle::LSP::Position.new(0, 9)
          ),
          message: "Unknown function 'button'.",
          code: "Lint/UnknownFunction"
        )

        context = Crinkle::LSP::CodeActionContext.new(diagnostics: [diagnostic])
        actions = provider.code_actions(uri, diagnostic.range, context, template)

        actions.size.should eq 1
        actions[0].title.should eq "Import 'button' from \"templates/macros.html.j2\""
      ensure
        FileUtils.rm_r(tmp_dir) if Dir.exists?(tmp_dir)
      end
    end

    it "suggests removing unused import names" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::CodeActionProvider.new(inference, ".")

      template = %({% from "macros.html.j2" import button, icon %}{{ button("ok") }})
      uri = "file:///test.j2"

      range = Crinkle::LSP::Range.new(
        Crinkle::LSP::Position.new(0, 35),
        Crinkle::LSP::Position.new(0, 40)
      )
      context = Crinkle::LSP::CodeActionContext.new(diagnostics: Array(Crinkle::LSP::Diagnostic).new)
      actions = provider.code_actions(uri, range, context, template)

      actions.size.should eq 1
      actions[0].title.should eq "Remove unused import 'icon'"
    end
  end
end
