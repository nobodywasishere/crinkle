require "spec"
require "./spec_helper"

# Phase 0 placeholder: fixtures exist and are loadable.

describe "fixtures" do
  it "loads template fixtures" do
    Dir.glob("fixtures/templates/*.j2").should_not be_empty
  end

  it "loads parser AST snapshots" do
    Dir.glob("fixtures/parser_ast/*.json").should_not be_empty
  end

  it "loads parser diagnostic snapshots" do
    Dir.glob("fixtures/parser_diagnostics/*.json").should_not be_empty
  end

  it "loads lexer snapshots" do
    Dir.glob("fixtures/lexer_tokens/*.json").should_not be_empty
    Dir.glob("fixtures/lexer_diagnostics/*.json").should_not be_empty
  end
end
