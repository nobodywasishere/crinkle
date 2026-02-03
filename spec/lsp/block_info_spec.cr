require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::BlockInfo do
    it "stores block information" do
      info = Crinkle::LSP::BlockInfo.new("content")

      info.name.should eq "content"
      info.definition_span.should be_nil
      info.source_uri.should be_nil
    end

    it "stores block information with span and source" do
      span = Crinkle::Span.new(
        Crinkle::Position.new(0, 0, 0),
        Crinkle::Position.new(0, 20, 20)
      )
      info = Crinkle::LSP::BlockInfo.new("header", span, "file:///base.j2")

      info.name.should eq "header"
      info.definition_span.should eq span
      info.source_uri.should eq "file:///base.j2"
    end
  end
end
