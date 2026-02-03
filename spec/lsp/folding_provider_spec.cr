require "../spec_helper"
require "../../src/lsp/lsp"
require "file_utils"

describe Crinkle::LSP do
  describe Crinkle::LSP::FoldingProvider do
    it "returns empty array for single-line template" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{{ name }}"

      ranges = provider.folding_ranges(template)

      ranges.should be_empty
    end

    it "creates folding range for multi-line block" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{% block content %}\nHello\n{% endblock %}"

      ranges = provider.folding_ranges(template)

      ranges.size.should eq 1
      ranges[0].start_line.should eq 0
      ranges[0].end_line.should eq 2
      ranges[0].kind.should eq Crinkle::LSP::FoldingRangeKind::Region
    end

    it "creates folding range for multi-line for loop" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{% for item in items %}\n{{ item }}\n{% endfor %}"

      ranges = provider.folding_ranges(template)

      ranges.size.should eq 1
      ranges[0].start_line.should eq 0
      ranges[0].end_line.should eq 2
    end

    it "creates folding range for multi-line if" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{% if x %}\ntrue\n{% endif %}"

      ranges = provider.folding_ranges(template)

      ranges.size.should eq 1
      ranges[0].start_line.should eq 0
      ranges[0].end_line.should eq 2
    end

    it "creates comment folding range" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{# This is a\nmulti-line\ncomment #}"

      ranges = provider.folding_ranges(template)

      ranges.size.should eq 1
      ranges[0].kind.should eq Crinkle::LSP::FoldingRangeKind::Comment
    end

    it "creates nested folding ranges" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{% block outer %}\n{% for i in items %}\n{{ i }}\n{% endfor %}\n{% endblock %}"

      ranges = provider.folding_ranges(template)

      ranges.size.should eq 2
    end

    it "handles parse errors gracefully" do
      provider = Crinkle::LSP::FoldingProvider.new
      template = "{% block unclosed"

      ranges = provider.folding_ranges(template)

      ranges.should be_empty
    end
  end
end
