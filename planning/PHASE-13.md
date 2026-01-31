# Phase 13 — Standard Library & Fixture Reorganization (Detailed Plan)

## Objectives
- Separate built-in filters, tests, and functions into an optional standard library
- Reorganize test fixtures into logical subdirectories
- Enable selective loading of builtins for customization
- Improve test organization and maintainability

## Priority
**HIGH** - Foundational for subsequent phases

## Motivation

Currently, all built-in filters, tests, and functions are registered directly in `Environment`. This phase creates an optional `src/std/` folder structure that allows:

1. **Selective inclusion** — Load only the builtins you need
2. **Clear separation** — Core engine vs standard library
3. **Easier testing** — Each builtin can be tested independently
4. **User overrides** — Users can replace builtins without modifying core

Similarly, the flat `fixtures/` directory makes it difficult to understand what each fixture tests. Organizing fixtures by pass (lexer, parser, renderer, etc.) improves maintainability.

## Scope (Phase 13)

### Standard Library (`src/std/`)

Create optional standard library with:

```
src/std/
├── filters/
│   ├── strings.cr      # upper, lower, capitalize, truncate, replace, etc.
│   ├── lists.cr        # first, last, join, map, select, selectattr, etc.
│   ├── numbers.cr      # int, float, round, abs, etc.
│   ├── html.cr         # escape, safe, urlize, urlencode
│   └── serialize.cr    # tojson, pprint
├── tests/
│   ├── types.cr        # defined, undefined, none, sequence, mapping, etc.
│   ├── comparison.cr   # eq, ne, lt, gt, le, ge
│   └── strings.cr      # upper, lower, etc.
├── functions/
│   ├── range.cr        # range()
│   ├── dict.cr         # dict()
│   └── debug.cr        # lipsum(), cycler(), joiner()
└── loader.cr           # Convenience loader for all/subset of std
```

### Fixture Reorganization

Reorganize flat `fixtures/` into:

```
fixtures/
├── lexer/           # Token-level tests (delimiters, whitespace, comments)
├── parser/          # AST construction tests (expressions, statements, nesting)
├── formatter/       # Formatting output tests (indentation, HTML-aware)
├── renderer/        # Execution/evaluation tests (control flow, output)
├── std/             # Standard library filter/test/function tests
│   ├── filters/
│   ├── tests/
│   └── functions/
└── integration/     # End-to-end tests combining multiple passes
```

Each subfolder follows existing naming convention:
- `<name>.<ext>.j2` — Template source
- `<name>.lexer.tokens.json` — Expected tokens
- `<name>.parser.ast.json` — Expected AST
- `<name>.renderer.output.txt` — Expected rendered output
- `<name>.diagnostics.json` — Expected diagnostics

## API Design

### Standard Library Loader

```crystal
# Default: load all builtins (backwards compatible)
env = Crinkle::Environment.new

# Load nothing
env = Crinkle::Environment.new(load_std: false)

# Load selectively
env.load_std_filters(Crinkle::Std::Filters::Category::Strings)
env.load_std_tests(Crinkle::Std::Tests::Category::Types)

# Load all of a specific type
env.load_std_filters(Crinkle::Std::Filters::Category::All)
```

### `src/std/loader.cr`

```crystal
module Crinkle
  module Std
    module Filters
      enum Category
        All
        Strings
        Lists
        Numbers
        Html
        Serialize
      end
    end

    module Tests
      enum Category
        All
        Types
        Comparison
        Strings
      end
    end

    module Functions
      enum Category
        All
        Range
        Dict
        Debug
      end
    end

    module Loader
      def self.load_all(env : Environment)
        load_filters(env, Filters::Category::All)
        load_tests(env, Tests::Category::All)
        load_functions(env, Functions::Category::All)
      end

      def self.load_filters(env : Environment, category : Filters::Category)
        case category
        when Filters::Category::All
          Filters::Strings.register(env)
          Filters::Lists.register(env)
          Filters::Numbers.register(env)
          Filters::Html.register(env)
          Filters::Serialize.register(env)
        when Filters::Category::Strings
          Filters::Strings.register(env)
        when Filters::Category::Lists
          Filters::Lists.register(env)
        # ... etc
        end
      end

      # Similar for tests and functions
    end
  end
end
```

### Filter Module Example

```crystal
# src/std/filters/strings.cr
module Crinkle::Std::Filters
  module Strings
    def self.register(env : Environment)
      env.register_filter("upper") do |value, _args, _kwargs|
        value.to_s.upcase
      end

      env.register_filter("lower") do |value, _args, _kwargs|
        value.to_s.downcase
      end

      env.register_filter("capitalize") do |value, _args, _kwargs|
        str = value.to_s
        return str if str.empty?
        str[0].upcase + str[1..]?.try(&.downcase) || ""
      end

      # ... more string filters
    end
  end
end
```

## Implementation Plan

### 1. Create `src/std/` Structure
- Create directory structure
- Move existing builtin implementations to appropriate modules
- Implement loader with selective loading

### 2. Update `Environment`
```crystal
def initialize(
  @override_builtins : Bool = false,
  @load_std : Bool = true,  # NEW: control std loading
  # ... other params
)
  # ...
  register_builtins if @load_std
end

private def register_builtins
  Std::Loader.load_all(self)
end

def load_std_filters(category : Std::Filters::Category)
  Std::Loader.load_filters(self, category)
end

def load_std_tests(category : Std::Tests::Category)
  Std::Loader.load_tests(self, category)
end

def load_std_functions(category : Std::Functions::Category)
  Std::Loader.load_functions(self, category)
end
```

### 3. Reorganize Fixtures
- Create subdirectories under `fixtures/`
- Move existing fixtures to appropriate subdirectories
- Update spec helpers to find fixtures in new locations
- Ensure all specs pass with new structure

### 4. Update Specs
- Update `fixtures_spec.cr` to handle subdirectories
- Add helper to glob fixtures from multiple directories
- Verify all snapshot tests still pass

### 5. Documentation
- Update README with selective loading examples
- Document fixture organization in AGENTS.md
- Add examples of custom filter/test registration

## Migration Strategy

### Backwards Compatibility

Maintain backwards compatibility by defaulting to loading all builtins:

```crystal
# Old code still works
env = Crinkle::Environment.new  # Loads all builtins

# New code can be selective
env = Crinkle::Environment.new(load_std: false)
env.load_std_filters(Crinkle::Std::Filters::Category::Strings)
```

### Fixture Migration

1. Create new directory structure
2. Copy fixtures to new locations (don't delete originals yet)
3. Update specs to use new locations
4. Verify all tests pass
5. Delete old fixtures

## Testing

### Standard Library Tests
```crystal
describe Crinkle::Std::Filters::Strings do
  it "registers upper filter" do
    env = Environment.new(load_std: false)
    Crinkle::Std::Filters::Strings.register(env)

    template = env.from_string("{{ name | upper }}")
    output = template.render({"name" => Crinkle.value("ada")})
    output.should eq("ADA")
  end
end
```

### Fixture Organization Tests
- Verify fixtures can be found in new locations
- Ensure snapshot helpers work with subdirectories
- Test that `Dir.glob("fixtures/**/*.j2")` finds all templates

## Acceptance Criteria

- [ ] `src/std/` directory created with organized modules
- [ ] Existing builtins moved to appropriate modules
- [ ] Loader supports selective loading
- [ ] Environment supports `load_std` parameter
- [ ] Fixtures reorganized into logical subdirectories
- [ ] All specs pass with new structure
- [ ] Documentation updated
- [ ] Backwards compatible (default loads all builtins)

## Checklist

### Standard Library
- [ ] Create `src/std/` directory structure
- [ ] Create `src/std/filters/strings.cr` with string filters
- [ ] Create `src/std/filters/lists.cr` with list filters
- [ ] Create `src/std/filters/numbers.cr` with number filters
- [ ] Create `src/std/filters/html.cr` with HTML filters
- [ ] Create `src/std/filters/serialize.cr` with serialization filters
- [ ] Create `src/std/tests/types.cr` with type tests
- [ ] Create `src/std/tests/comparison.cr` with comparison tests
- [ ] Create `src/std/functions/` with builtin functions
- [ ] Create `src/std/loader.cr` with selective loading API
- [ ] Update `Environment` to support `load_std` option

### Fixture Reorganization
- [ ] Create `fixtures/lexer/` and migrate lexer-focused fixtures
- [ ] Create `fixtures/parser/` and migrate parser-focused fixtures
- [ ] Create `fixtures/formatter/` and migrate formatter-focused fixtures
- [ ] Create `fixtures/renderer/` and migrate renderer-focused fixtures
- [ ] Create `fixtures/std/` for builtin tests
- [ ] Create `fixtures/integration/` for end-to-end tests
- [ ] Update spec helpers to find fixtures in new locations
- [ ] Ensure all existing specs pass with new structure

### Documentation
- [ ] Update README with selective loading examples
- [ ] Update AGENTS.md with fixture organization
- [ ] Add examples of custom filter/test registration

## Out of Scope

- Implementing new filters/tests (covered in Phases 15-16)
- Performance optimization of builtin loading
- Dynamic plugin system for third-party extensions
- Packaging std library as separate shard

## Notes

This phase is foundational for Phases 14-19, which add new builtins and APIs. Having a clean standard library structure makes it easier to add and document new features.
