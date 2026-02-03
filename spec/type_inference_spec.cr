require "./spec_helper"

private def collect_target_names(target : Crinkle::AST::Target) : Array(String)
  case target
  when Crinkle::AST::Name
    [target.value]
  when Crinkle::AST::TupleLiteral
    target.items.compact_map do |item|
      item.is_a?(Crinkle::AST::Name) ? item.value : nil
    end
  else
    Array(String).new
  end
end

private def infer_types(template : Crinkle::AST::Template, schema : Crinkle::Schema::Registry) : JSON::Any
  inferer = Crinkle::TypeInference::Inferer.new(schema)
  env = Crinkle::TypeInference::Environment.new
  types = Hash(String, String).new

  Crinkle::AST::Walker.walk_nodes(template.body) do |node|
    case node
    when Crinkle::AST::Set
      type = inferer.infer_expr_type(node.value, env)
      next unless type
      collect_target_names(node.target).each do |name|
        types[name] = type.to_s
        env.set(name, type)
      end
    when Crinkle::AST::SetBlock
      type = Crinkle::TypeInference::TypeRef.new("String")
      collect_target_names(node.target).each do |name|
        types[name] = type.to_s
        env.set(name, type)
      end
    when Crinkle::AST::Macro
      node.params.each do |param|
        next unless param.default_value
        default_value = param.default_value
        next unless default_value
        param_type = inferer.infer_expr_type(default_value, env)
        next unless param_type
        types["#{node.name}.#{param.name}"] = param_type.to_s
      end
    end
  end

  JSON.parse(types.to_json)
end

describe "Type inference" do
  it "infers types for literals, filters, tests, and functions" do
    source = File.read("fixtures/type_inference/basic.html.j2")
    lexer = Crinkle::Lexer.new(source)
    tokens = lexer.lex_all
    parser = Crinkle::Parser.new(tokens)
    template = parser.parse

    schema = Crinkle::Schema::Registry.new
    schema.register_filter(Crinkle::Schema::FilterSchema.new(name: "upper", returns: "String"))
    schema.register_test(Crinkle::Schema::TestSchema.new(name: "even"))
    schema.register_function(Crinkle::Schema::FunctionSchema.new(name: "range", returns: "Array"))

    actual = infer_types(template, schema)
    assert_snapshot("fixtures/type_inference/basic.type_inference.json", actual)
  end
end
