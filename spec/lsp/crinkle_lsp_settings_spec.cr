require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::CrinkleLspSettings do
    it "has default values" do
      settings = Crinkle::LSP::CrinkleLspSettings.new
      settings.lint_enabled?.should be_true
      settings.max_file_size.should eq 1_000_000
      settings.debounce_ms.should eq 150
      settings.typo_detection?.should be_true
    end

    it "deserializes from JSON" do
      json = %({"lintEnabled": false, "maxFileSize": 500000, "debounceMs": 200, "typoDetection": false})
      settings = Crinkle::LSP::CrinkleLspSettings.from_json(json)

      settings.lint_enabled?.should be_false
      settings.max_file_size.should eq 500000
      settings.debounce_ms.should eq 200
      settings.typo_detection?.should be_false
    end

    it "uses defaults for missing fields" do
      json = %({"lintEnabled": false})
      settings = Crinkle::LSP::CrinkleLspSettings.from_json(json)

      settings.lint_enabled?.should be_false
      settings.max_file_size.should eq 1_000_000 # default
      settings.debounce_ms.should eq 150         # default
      settings.typo_detection?.should be_true    # default
    end

    it "serializes to JSON" do
      settings = Crinkle::LSP::CrinkleLspSettings.new(
        lint_enabled: false,
        max_file_size: 2_000_000,
        debounce_ms: 100,
        typo_detection: false
      )
      json = settings.to_json
      parsed = JSON.parse(json)

      parsed["lintEnabled"].as_bool.should be_false
      parsed["maxFileSize"].should eq 2_000_000
      parsed["debounceMs"].should eq 100
      parsed["typoDetection"].as_bool.should be_false
    end
  end
end
