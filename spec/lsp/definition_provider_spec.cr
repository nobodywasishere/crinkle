require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::DefinitionProvider do
    it "returns nil for extends when file does not exist" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = %({% extends "nonexistent.j2" %})

      # Position inside the quoted string
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 15))

      # Location should be nil because file doesn't exist
      location.should be_nil
    end

    it "returns nil for include when file does not exist" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = %({% include "nonexistent.j2" %})

      # Position inside the quoted string
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 14))

      # Location should be nil because file doesn't exist
      location.should be_nil
    end

    it "returns nil for position outside template reference" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      provider = Crinkle::LSP::DefinitionProvider.new(inference, ".")

      template = %(Hello {% extends "base.j2" %})

      # Position at "Hello"
      location = provider.definition("file:///test.j2", template, Crinkle::LSP::Position.new(0, 2))

      location.should be_nil
    end

    it "returns location for existing file" do
      config = Crinkle::LSP::Config.new
      inference = Crinkle::LSP::InferenceEngine.new(config)
      # Use actual spec directory as root
      provider = Crinkle::LSP::DefinitionProvider.new(inference, "spec")

      # Reference spec_helper.cr which exists in spec/
      template = %({% extends "spec_helper.cr" %})

      # Position inside the quoted string
      location = provider.definition("file:///spec/test.j2", template, Crinkle::LSP::Position.new(0, 15))

      location.should_not be_nil
      if loc = location
        loc.uri.should contain "spec_helper.cr"
      end
    end
  end
end
