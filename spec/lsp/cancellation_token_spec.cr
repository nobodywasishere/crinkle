require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::CancellationToken do
    it "starts uncancelled" do
      token = Crinkle::LSP::CancellationToken.new
      token.cancelled?.should be_false
    end

    it "can be cancelled" do
      token = Crinkle::LSP::CancellationToken.new
      token.cancel
      token.cancelled?.should be_true
    end

    it "remains cancelled after multiple cancel calls" do
      token = Crinkle::LSP::CancellationToken.new
      token.cancel
      token.cancel
      token.cancelled?.should be_true
    end
  end
end
