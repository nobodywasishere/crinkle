require "spec"
require "./spec_helper"

# Phase 0 placeholder: fixtures exist and are loadable.

describe "fixtures" do
  it "loads template fixtures" do
    Dir.glob("fixtures/templates/*.j2").should_not be_empty
  end

  it "loads AST snapshots" do
    Dir.glob("fixtures/ast/*.json").should_not be_empty
  end

  it "loads diagnostic snapshots" do
    Dir.glob("fixtures/diagnostics/*.json").should_not be_empty
  end
end
