# Phase 18 — Template Loading API (Detailed Plan)

## Objectives
- Provide high-level API for loading and rendering templates.
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
- Implement `get_template`, `from_string`, `render` methods.
- Add `TemplateNotFoundError` exception.

## Design Decision: No Caching

Template caching was intentionally omitted to keep the implementation simple. Each `get_template` call parses the template fresh. This approach:

- Simplifies the API (no `cache_enabled`, `auto_reload`, `clear_cache`)
- Avoids cache invalidation complexity
- Works well for development workflows
- Leaves caching as a user-space concern if needed

Users who need caching can implement it themselves:
```crystal
# User-space caching example
class CachedEnvironment
  @cache = Hash(String, Crinkle::Template).new
  @env : Crinkle::Environment

  def get_template(name : String) : Crinkle::Template
    @cache[name] ||= @env.get_template(name)
  end
end
```

## File Structure
```
src/
  template.cr           # Template class
  environment.cr        # Modified with loading
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

    def render(context : Hash(String, Value) = Hash(String, Value).new) : String
      env = @environment || Environment.new
      renderer = Renderer.new(env)
      renderer.render(@ast, context)
    end

    def render(**variables) : String
      # Convert named arguments to context hash
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

### Environment Methods
```crystal
class Environment
  # Get template by name (parses fresh each call)
  def get_template(name : String) : Template
    source = load_template_source(name)
    parse_template(source, name)
  end

  # Parse template from string
  def from_string(source : String, name : String? = nil) : Template
    parse_template(source, name || "<string>")
  end

  # Quick render
  def render(template_name : String, context = Hash(String, Value).new) : String
    get_template(template_name).render(context)
  end

  def render(template_name : String, **variables) : String
    # Convert named arguments and render
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
output = template.render(title: "Hello World")

# Or quick render
output = env.render("page.html.j2", title: "Hello World")

# From string
template = env.from_string("Hello {{ name }}!")
output = template.render(name: "World")
```

## Acceptance Criteria
- `Template` class wraps AST and provides `render` method.
- `Environment.get_template` loads templates from configured loader.
- `Environment.from_string` parses templates from strings.
- `TemplateNotFoundError` raised when template not found.

## Checklist
- [x] Create `src/template.cr` with Template class
- [x] Add `TemplateNotFoundError` exception
- [x] Add `get_template` method to Environment
- [x] Add `from_string` method to Environment
- [x] Add `render` convenience method to Environment
- [x] Add `require` to `src/crinkle.cr`
- [x] Add specs for template loading
