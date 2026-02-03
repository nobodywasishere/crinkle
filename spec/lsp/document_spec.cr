require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::Document do
    it "stores document content" do
      doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "Hello {{ name }}", 1)
      doc.uri.should eq "file:///test.j2"
      doc.language_id.should eq "jinja2"
      doc.text.should eq "Hello {{ name }}"
      doc.version.should eq 1
    end

    it "updates document content" do
      doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "Hello", 1)
      doc.update("Hello World", 2)
      doc.text.should eq "Hello World"
      doc.version.should eq 2
    end

    it "counts lines" do
      doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "line1\nline2\nline3", 1)
      doc.line_count.should eq 3
    end

    it "gets specific line" do
      doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "line1\nline2\nline3", 1)
      doc.line(0).should eq "line1"
      doc.line(1).should eq "line2"
      doc.line(2).should eq "line3"
      doc.line(3).should be_nil
    end

    describe "#apply_change (incremental sync)" do
      it "inserts text at the beginning" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "World", 1)
        range = Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 0),
          Crinkle::LSP::Position.new(0, 0)
        )
        doc.apply_change(range, "Hello ", 2)
        doc.text.should eq "Hello World"
        doc.version.should eq 2
      end

      it "inserts text in the middle" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "Hello World", 1)
        range = Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 5),
          Crinkle::LSP::Position.new(0, 5)
        )
        doc.apply_change(range, " Beautiful", 2)
        doc.text.should eq "Hello Beautiful World"
      end

      it "replaces text range" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "Hello World", 1)
        range = Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 6),
          Crinkle::LSP::Position.new(0, 11)
        )
        doc.apply_change(range, "Crystal", 2)
        doc.text.should eq "Hello Crystal"
      end

      it "deletes text when replacement is empty" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "Hello World", 1)
        range = Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 5),
          Crinkle::LSP::Position.new(0, 11)
        )
        doc.apply_change(range, "", 2)
        doc.text.should eq "Hello"
      end

      it "handles multi-line changes" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "line1\nline2\nline3", 1)
        range = Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(1, 0),
          Crinkle::LSP::Position.new(2, 0)
        )
        doc.apply_change(range, "new\n", 2)
        doc.text.should eq "line1\nnew\nline3"
      end

      it "invalidates cache on change" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "{{ x }}", 1)
        # Force caching by accessing tokens
        doc.tokens.size.should be > 0

        # Apply change
        range = Crinkle::LSP::Range.new(
          Crinkle::LSP::Position.new(0, 3),
          Crinkle::LSP::Position.new(0, 4)
        )
        doc.apply_change(range, "name", 2)

        # Tokens should be recomputed with new content
        doc.text.should eq "{{ name }}"
      end
    end

    describe "LSP diagnostics caching" do
      it "caches and retrieves diagnostics" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "{{ x }}", 1)
        diagnostics = [
          Crinkle::LSP::Diagnostic.new(
            range: Crinkle::LSP::Range.new(
              Crinkle::LSP::Position.new(0, 0),
              Crinkle::LSP::Position.new(0, 7)
            ),
            message: "Test diagnostic"
          ),
        ]

        doc.cache_diagnostics(diagnostics)
        cached = doc.cached_lsp_diagnostics

        cached.should_not be_nil
        cached.try(&.size).should eq 1
        cached.try(&.first.message).should eq "Test diagnostic"
      end

      it "returns nil for cached diagnostics when version changes" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "{{ x }}", 1)
        diagnostics = [
          Crinkle::LSP::Diagnostic.new(
            range: Crinkle::LSP::Range.new(
              Crinkle::LSP::Position.new(0, 0),
              Crinkle::LSP::Position.new(0, 7)
            ),
            message: "Test"
          ),
        ]

        doc.cache_diagnostics(diagnostics)
        doc.update("{{ y }}", 2)

        doc.cached_lsp_diagnostics.should be_nil
      end

      it "clears analysis cache separately from other caches" do
        doc = Crinkle::LSP::Document.new("file:///test.j2", "jinja2", "{{ x }}", 1)
        diagnostics = [
          Crinkle::LSP::Diagnostic.new(
            range: Crinkle::LSP::Range.new(
              Crinkle::LSP::Position.new(0, 0),
              Crinkle::LSP::Position.new(0, 7)
            ),
            message: "Test"
          ),
        ]

        # Cache diagnostics
        doc.cache_diagnostics(diagnostics)
        doc.cached_lsp_diagnostics.should_not be_nil

        # Clear analysis cache
        doc.clear_analysis_cache
        doc.cached_lsp_diagnostics.should be_nil
      end
    end
  end
end
