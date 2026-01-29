require "spec"
require "json"
require "../src/jinja"

def tokens_to_json(tokens : Array(Jinja::Token)) : JSON::Any
  payload = tokens.map do |token|
    {
      "type"   => token.type.to_s,
      "lexeme" => token.lexeme,
      "span"   => {
        "start" => {
          "offset" => token.span.start_pos.offset,
          "line"   => token.span.start_pos.line,
          "column" => token.span.start_pos.column,
        },
        "end" => {
          "offset" => token.span.end_pos.offset,
          "line"   => token.span.end_pos.line,
          "column" => token.span.end_pos.column,
        },
      },
    }
  end

  JSON.parse(payload.to_json)
end

def diagnostics_to_json(diags : Array(Jinja::Diagnostic)) : JSON::Any
  payload = diags.map do |diag|
    {
      "id"       => diag.id,
      "severity" => diag.severity.to_s.downcase,
      "message"  => diag.message,
      "span"     => {
        "start" => {
          "offset" => diag.span.start_pos.offset,
          "line"   => diag.span.start_pos.line,
          "column" => diag.span.start_pos.column,
        },
        "end" => {
          "offset" => diag.span.end_pos.offset,
          "line"   => diag.span.end_pos.line,
          "column" => diag.span.end_pos.column,
        },
      },
    }
  end

  JSON.parse(payload.to_json)
end

def assert_snapshot(path : String, actual : JSON::Any) : Nil
  if File.exists?(path)
    expected = JSON.parse(File.read(path))
    if actual != expected
      File.write(path, actual.to_pretty_json)
      raise "Snapshot mismatch for #{path}. Updated snapshot."
    end
  else
    File.write(path, actual.to_pretty_json)
    raise "Snapshot missing for #{path}. Created snapshot."
  end
end

def assert_text_snapshot(path : String, actual : String) : Nil
  if actual.empty?
    File.delete(path) if File.exists?(path)
    return
  end

  if File.exists?(path)
    expected = File.read(path)
    if actual != expected
      File.write(path, actual)
      raise "Snapshot mismatch for #{path}. Updated snapshot."
    end
  else
    File.write(path, actual)
    raise "Snapshot missing for #{path}. Created snapshot."
  end
end

def assert_diagnostics_snapshot(path : String, diags : Array(Jinja::Diagnostic)) : Nil
  if diags.empty?
    File.delete(path) if File.exists?(path)
    return
  end

  assert_snapshot(path, diagnostics_to_json(diags))
end
