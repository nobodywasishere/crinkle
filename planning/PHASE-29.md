# Phase 29 — MCP Prompts (AI Assistance) (Detailed Plan)

## Objectives
- Define pre-built prompts for common AI-assisted template tasks.
- Enable intelligent template assistance workflows.
- Provide structured guidance for AI template analysis.

## Priority
**LOW**

## Background

MCP prompts are pre-defined templates that AI assistants can use to structure their interactions. They help AI assistants understand context and provide consistent, high-quality assistance for specific tasks.

## Scope (Phase 29)
- Define prompt templates for template analysis tasks
- Implement prompt handlers
- Provide argument schemas for each prompt
- Return structured prompt content

## File Structure
```
src/
  mcp/
    prompts.cr              # Prompt registry and definitions
```

## Prompts Specification

### 1. explain-template
**Description:** Explain what a template does in plain language.

**Arguments:**
```json
{
  "type": "object",
  "properties": {
    "source": {
      "type": "string",
      "description": "Template source code"
    },
    "detail_level": {
      "type": "string",
      "enum": ["brief", "detailed", "exhaustive"],
      "default": "detailed",
      "description": "Level of detail in explanation"
    }
  },
  "required": ["source"]
}
```

**Generated Prompt:**
```
Analyze this Jinja2 template and explain what it does:

```jinja2
{source}
```

{if detail_level == "brief"}
Provide a 1-2 sentence summary of the template's purpose.
{else if detail_level == "detailed"}
Explain:
1. The overall purpose of the template
2. What data/context variables it expects
3. The key control flow (conditionals, loops)
4. What output it produces
{else}
Provide an exhaustive analysis including:
1. Line-by-line breakdown
2. All required context variables with expected types
3. Control flow diagram
4. Edge cases and potential issues
5. Suggestions for improvement
{endif}
```

### 2. find-context-vars
**Description:** Infer required context variables from template usage.

**Arguments:**
```json
{
  "type": "object",
  "properties": {
    "source": {
      "type": "string",
      "description": "Template source code"
    },
    "output_format": {
      "type": "string",
      "enum": ["list", "typescript", "crystal", "json_schema"],
      "default": "list",
      "description": "Format for variable definitions"
    }
  },
  "required": ["source"]
}
```

**Generated Prompt:**
```
Analyze this Jinja2 template and identify all required context variables:

```jinja2
{source}
```

For each variable, determine:
1. Name
2. Inferred type (string, number, boolean, array, object)
3. Whether it's required or optional
4. How it's used in the template

{if output_format == "typescript"}
Output as TypeScript interface:
```typescript
interface TemplateContext {
  // ...
}
```
{else if output_format == "crystal"}
Output as Crystal class:
```crystal
class TemplateContext
  # ...
end
```
{else if output_format == "json_schema"}
Output as JSON Schema:
```json
{
  "type": "object",
  "properties": { ... }
}
```
{else}
Output as a markdown list with type annotations.
{endif}
```

### 3. debug-error
**Description:** Get human-friendly explanation of template error.

**Arguments:**
```json
{
  "type": "object",
  "properties": {
    "source": {
      "type": "string",
      "description": "Template source code"
    },
    "error": {
      "type": "object",
      "description": "Error diagnostic from crinkle",
      "properties": {
        "code": { "type": "string" },
        "message": { "type": "string" },
        "line": { "type": "integer" },
        "column": { "type": "integer" }
      }
    },
    "context": {
      "type": "object",
      "description": "Context variables that were passed (if available)"
    }
  },
  "required": ["source", "error"]
}
```

**Generated Prompt:**
```
A Jinja2 template has the following error:

**Error:** {error.message}
**Code:** {error.code}
**Location:** Line {error.line}, Column {error.column}

Template source:
```jinja2
{source with error line highlighted}
```

{if context}
Context provided:
```json
{context}
```
{endif}

Please:
1. Explain what this error means in simple terms
2. Identify the likely cause
3. Suggest specific fixes with code examples
4. Explain how to prevent similar errors
```

### 4. suggest-filters
**Description:** Suggest appropriate filters for a value transformation.

**Arguments:**
```json
{
  "type": "object",
  "properties": {
    "input_type": {
      "type": "string",
      "description": "Type of input value (string, number, array, object)"
    },
    "desired_output": {
      "type": "string",
      "description": "Description of desired transformation"
    },
    "example_input": {
      "type": "string",
      "description": "Example input value"
    },
    "example_output": {
      "type": "string",
      "description": "Desired output value"
    }
  },
  "required": ["desired_output"]
}
```

**Generated Prompt:**
```
I need to transform a value in a Jinja2 template.

{if input_type}
**Input type:** {input_type}
{endif}

**Desired transformation:** {desired_output}

{if example_input && example_output}
**Example:**
- Input: `{example_input}`
- Desired output: `{example_output}`
{endif}

Please suggest:
1. The best Jinja2 filter(s) to achieve this
2. Complete template syntax with the filter(s)
3. Alternative approaches if multiple options exist
4. Any edge cases to consider

Use only filters available in crinkle/Jinja2.
```

### 5. convert-template
**Description:** Help migrate from other template engines.

**Arguments:**
```json
{
  "type": "object",
  "properties": {
    "source": {
      "type": "string",
      "description": "Template source in original syntax"
    },
    "from_engine": {
      "type": "string",
      "enum": ["erb", "handlebars", "liquid", "mustache", "django", "pug"],
      "description": "Original template engine"
    }
  },
  "required": ["source", "from_engine"]
}
```

**Generated Prompt:**
```
Convert this {from_engine} template to Jinja2 syntax:

```{from_engine}
{source}
```

Please:
1. Convert the syntax to equivalent Jinja2
2. Note any features that don't have direct equivalents
3. Suggest idiomatic Jinja2 alternatives where needed
4. List any custom helpers/filters that need to be implemented
5. Provide the complete converted template

Output the converted template in a code block:
```jinja2
{converted template}
```
```

### 6. generate-tests
**Description:** Generate test cases for a template.

**Arguments:**
```json
{
  "type": "object",
  "properties": {
    "source": {
      "type": "string",
      "description": "Template source code"
    },
    "test_framework": {
      "type": "string",
      "enum": ["crystal_spec", "jest", "pytest", "generic"],
      "default": "generic",
      "description": "Test framework format"
    },
    "coverage": {
      "type": "string",
      "enum": ["basic", "thorough", "exhaustive"],
      "default": "thorough",
      "description": "Test coverage level"
    }
  },
  "required": ["source"]
}
```

**Generated Prompt:**
```
Generate test cases for this Jinja2 template:

```jinja2
{source}
```

{if coverage == "basic"}
Generate basic happy-path tests.
{else if coverage == "thorough"}
Generate tests covering:
- Happy path with typical data
- Edge cases (empty arrays, null values, missing keys)
- Boundary conditions
{else}
Generate exhaustive tests including:
- All code paths
- All edge cases
- Error conditions
- Performance considerations
- Security-relevant inputs (XSS vectors)
{endif}

{if test_framework == "crystal_spec"}
Output as Crystal spec tests:
```crystal
describe "template" do
  # ...
end
```
{else if test_framework == "jest"}
Output as Jest tests:
```javascript
describe("template", () => {
  // ...
});
```
{else}
Output as test cases with:
- Test name
- Input context
- Expected output
- Description
{endif}

For each test, provide the context object and expected rendered output.
```

## API Design

### Prompt Registry
```crystal
module Crinkle::MCP
  class PromptRegistry
    @prompts : Hash(String, Prompt)

    def initialize
      @prompts = {} of String => Prompt
      register_builtin_prompts
    end

    def list : Array(PromptDefinition)
      @prompts.values.map(&.definition)
    end

    def get(name : String, arguments : JSON::Any) : PromptContent
      prompt = @prompts[name]?
      raise PromptNotFound.new(name) unless prompt
      prompt.generate(arguments)
    end

    private def register_builtin_prompts
      register(ExplainTemplatePrompt.new)
      register(FindContextVarsPrompt.new)
      register(DebugErrorPrompt.new)
      register(SuggestFiltersPrompt.new)
      register(ConvertTemplatePrompt.new)
      register(GenerateTestsPrompt.new)
    end
  end

  abstract class Prompt
    abstract def name : String
    abstract def description : String
    abstract def arguments_schema : JSON::Any
    abstract def generate(arguments : JSON::Any) : PromptContent

    def definition : PromptDefinition
      PromptDefinition.new(
        name: name,
        description: description,
        arguments: arguments_schema
      )
    end
  end

  struct PromptContent
    getter messages : Array(PromptMessage)
  end

  struct PromptMessage
    getter role : String  # "user" or "assistant"
    getter content : String
  end
end
```

### Example Prompt Implementation
```crystal
module Crinkle::MCP::Prompts
  class ExplainTemplatePrompt < Prompt
    def name : String
      "explain-template"
    end

    def description : String
      "Explain what a Jinja2 template does in plain language"
    end

    def arguments_schema : JSON::Any
      JSON.parse(<<-JSON)
        {
          "type": "object",
          "properties": {
            "source": {
              "type": "string",
              "description": "Template source code"
            },
            "detail_level": {
              "type": "string",
              "enum": ["brief", "detailed", "exhaustive"],
              "default": "detailed"
            }
          },
          "required": ["source"]
        }
      JSON
    end

    def generate(arguments : JSON::Any) : PromptContent
      source = arguments["source"].as_s
      detail = arguments["detail_level"]?.try(&.as_s) || "detailed"

      content = String.build do |s|
        s << "Analyze this Jinja2 template and explain what it does:\n\n"
        s << "```jinja2\n#{source}\n```\n\n"

        case detail
        when "brief"
          s << "Provide a 1-2 sentence summary of the template's purpose."
        when "detailed"
          s << "Explain:\n"
          s << "1. The overall purpose of the template\n"
          s << "2. What data/context variables it expects\n"
          s << "3. The key control flow (conditionals, loops)\n"
          s << "4. What output it produces"
        when "exhaustive"
          s << "Provide an exhaustive analysis including:\n"
          s << "1. Line-by-line breakdown\n"
          s << "2. All required context variables with expected types\n"
          s << "3. Control flow diagram\n"
          s << "4. Edge cases and potential issues\n"
          s << "5. Suggestions for improvement"
        end
      end

      PromptContent.new(messages: [
        PromptMessage.new(role: "user", content: content)
      ])
    end
  end
end
```

## Acceptance Criteria
- All 6 prompts implemented and registered
- Prompts return well-structured content
- Arguments validated against schema
- `prompts/list` returns all prompt definitions
- `prompts/get` generates appropriate prompt content
- Prompts provide useful guidance for AI assistants

## Checklist
- [ ] Create prompt registry and base class
- [ ] Implement `explain-template` prompt
- [ ] Implement `find-context-vars` prompt
- [ ] Implement `debug-error` prompt
- [ ] Implement `suggest-filters` prompt
- [ ] Implement `convert-template` prompt
- [ ] Implement `generate-tests` prompt
- [ ] Wire prompts into MCP server
- [ ] Add argument validation
- [ ] Test each prompt with AI assistant
- [ ] Document prompt usage patterns

## Dependencies
- Phase 26 (MCP Foundation)

## Usage Patterns

### In Claude Code
```
User: "Explain what this template does"
Claude: [Uses explain-template prompt with user's template]

User: "What context does this template need?"
Claude: [Uses find-context-vars prompt]

User: "I'm getting an error on line 5"
Claude: [Uses debug-error prompt with error details]

User: "How do I format this as currency?"
Claude: [Uses suggest-filters prompt]

User: "Convert this ERB template to Jinja2"
Claude: [Uses convert-template prompt]

User: "Generate tests for this template"
Claude: [Uses generate-tests prompt]
```

## Testing Strategy
- Unit tests for prompt generation
- Integration tests via MCP protocol
- Verify prompt content quality manually
- Test with actual AI assistant interactions
