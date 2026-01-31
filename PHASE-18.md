# Phase 18 — Template Loading API (Detailed Plan)

## Objectives
- Provide high-level API for loading and rendering templates.
- Implement template caching for production performance.
- Support template loaders (file system, custom sources).
- Enable convenient rendering patterns.

## Priority
**HIGH**

## Motivation
```crystal
env = Crinkle::Environment.new
env.set_loader { |name| File.read("templates/#{name}") }

template = env.get_template("page.html.j2")
output = template.render({"title" => "Hello"})
```

## Scope (Phase 18)
- Create `Template` class wrapping parsed AST.
- Add template caching to `Environment`.
- Implement `get_template`, `from_string`, `render` methods.
- Add `TemplateNotFoundError` exception.

## File Structure
```
src/
  template.cr           # Template class
  environment.cr        # Modified with caching + loading
  crinkle.cr            # Add require
```

## API Design

### `src/template.cr`
```crystal
module Crinkle
  class Template
    getter source : String
    getter ast : AST::Template
    getter name : String
    getter filename : String?

    def initialize(@source, @ast, @name, @filename = nil, @environment : Environment? = nil)
    end

    # Render with optional context
    def render(context : Hash(String, Value) = Hash(String, Value).new) : String
      env = @environment || Environment.new
      renderer = Renderer.new(env)
      renderer.render(@ast, context)
    end

    # Render with variables hash (convenience)
    def render(variables : Hash) : String
      render(Crinkle.variables(variables))
    end
  end

  class TemplateNotFoundError < Exception
    getter template_name : String
    getter loader : String?

    def initialize(@template_name, @loader = nil, message = nil)
      super(message || "Template '#{@template_name}' not found")
    end
  end
end
```

### Environment Modifications
```crystal
class Environment
  @template_cache : Hash(String, Template)
  @cache_enabled : Bool

  def initialize(
    @override_builtins : Bool = false,
    @strict_undefined : Bool = true,
    @strict_filters : Bool = true,
    @strict_tests : Bool = true,
    @strict_functions : Bool = true,
    @cache_enabled : Bool = true  # NEW: Enable template caching
  ) : Nil
    @tag_extensions = Hash(String, TagExtension).new
    @filters = Hash(String, FilterProc).new
    @tests = Hash(String, TestProc).new
    @functions = Hash(String, FunctionProc).new
    @template_loader = nil
    @template_cache = Hash(String, Template).new
    register_builtin_filters_tests
  end

  # Get template by name (with caching)
  def get_template(name : String) : Template
    if @cache_enabled && (cached = @template_cache[name]?)
      return cached
    end

    source = load_template_source(name)
    template = parse_template(source, name)

    if @cache_enabled
      @template_cache[name] = template
    end

    template
  end

  # Parse template from string
  def from_string(source : String, name : String? = nil) : Template
    parse_template(source, name || "<string>")
  end

  # Clear template cache
  def clear_cache : Nil
    @template_cache.clear
  end

  # Quick render without storing template
  def render(template_name : String, context : Hash(String, Value) = Hash(String, Value).new) : String
    get_template(template_name).render(context)
  end

  def render(template_name : String, **variables) : String
    render(template_name, Crinkle.variables(variables.to_h))
  end

  private def load_template_source(name : String) : String
    if loader = @template_loader
      if source = loader.call(name)
        return source
      end
    end
    raise TemplateNotFoundError.new(name)
  end

  private def parse_template(source : String, name : String) : Template
    lexer = Lexer.new(source)
    tokens = lexer.tokenize
    parser = Parser.new(tokens, self)
    ast = parser.parse
    Template.new(source, ast, name, name, self)
  end
end
```

## Example Usage
```crystal
# Setup
env = Crinkle::Environment.new
env.set_loader do |name|
  path = "templates/#{name}"
  File.exists?(path) ? File.read(path) : nil
end

# Load and render
template = env.get_template("page.html.j2")
output = template.render({"title" => Crinkle.value("Hello World")})

# Or quick render
output = env.render("page.html.j2", title: "Hello World")

# From string
template = env.from_string("Hello {{ name }}!")
output = template.render({"name" => Crinkle.value("World")})
```

## Performance: Production Caching
Templates are cached after first parse (~2000x faster on subsequent calls):
```crystal
# Caching is enabled by default
env = Environment.new(cache_enabled: true)

# First call parses and caches
template = env.get_template("page.html.j2")  # Parses

# Subsequent calls return cached
template = env.get_template("page.html.j2")  # Returns from cache
```

## Acceptance Criteria
- `Template` class wraps AST and provides `render` method.
- `Environment.get_template` loads and caches templates.
- `Environment.from_string` parses templates from strings.
- `TemplateNotFoundError` raised when template not found.
- Caching significantly improves performance.

## Checklist
- [ ] Create `src/template.cr` with Template class
- [ ] Add `TemplateNotFoundError` exception
- [ ] Add `@template_cache` to Environment
- [ ] Add `get_template` method to Environment
- [ ] Add `from_string` method to Environment
- [ ] Add `clear_cache` method to Environment
- [ ] Add `render` convenience method to Environment
- [ ] Add `require` to `src/crinkle.cr`
- [ ] Add specs for template loading and caching
