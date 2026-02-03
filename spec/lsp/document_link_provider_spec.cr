require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::DocumentLinkProvider do
    it "creates links for extends statements" do
      provider = Crinkle::LSP::DocumentLinkProvider.new("spec")

      # Use spec_helper.cr which exists
      template = %({% extends "spec_helper.cr" %})

      links = provider.links("file:///spec/test.j2", template)

      links.size.should eq 1
      links[0].tooltip.try(&.includes?("spec_helper.cr")).should be_true
    end

    it "returns empty for non-existent templates" do
      provider = Crinkle::LSP::DocumentLinkProvider.new(".")

      template = %({% extends "nonexistent.j2" %})

      links = provider.links("file:///test.j2", template)

      links.should be_empty
    end

    it "creates links for include statements" do
      provider = Crinkle::LSP::DocumentLinkProvider.new("spec")

      template = %({% include "spec_helper.cr" %})

      links = provider.links("file:///spec/test.j2", template)

      links.size.should eq 1
    end
  end
end
