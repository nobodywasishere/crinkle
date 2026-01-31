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
├── lexer/           # Token-level tests (delimiters, whitespace, comments) - 9 fixtures
├── parser/          # AST construction tests (expressions, statements, nesting) - 77 fixtures
├── formatter/       # Formatting output tests (indentation, HTML-aware) - 51 fixtures
├── linter/          # Linter rule tests - 11 fixtures
├── renderer/        # Execution/evaluation tests (control flow, output) - 22 fixtures
├── std_filters/     # Standard library filter tests - 1 fixture
├── std_tests/       # Standard library test tests - 1 fixture
├── std_functions/   # Standard library function tests - empty
├── integration/     # End-to-end tests combining multiple passes - 6 fixtures
└── extensions/      # Extension tag tests (unchanged) - 6 fixtures
```

Each subfolder follows existing naming convention:
- `<name>.<ext>.j2` — Template source
- `<name>.lexer.tokens.json` — Expected tokens
- `<name>.parser.ast.json` — Expected AST
- `<name>.renderer.output.txt` — Expected rendered output
- `<name>.diagnostics.json` — Expected diagnostics

Total: 174 main fixtures + 6 extension fixtures = 180 template files, generating 185 test cases.

## API Design

### Standard Library Loader

```crystal
# Default: load all builtins (backwards compatible)
env = Crinkle::Environment.new

# Load nothing, add selectively
env = Crinkle::Environment.new(load_std: false)
Crinkle::Std::Filters::Strings.register(env)
Crinkle::Std::Tests::Types.register(env)
```

### `src/std/loader.cr`

```crystal
module Crinkle::Std
  def self.load_all(env : Environment)
    # Filters
    Filters::Strings.register(env)
    Filters::Lists.register(env)
    Filters::Numbers.register(env)
    Filters::Html.register(env)
    Filters::Serialize.register(env)

    # Tests
    Tests::Types.register(env)
    Tests::Comparison.register(env)
    Tests::Strings.register(env)

    # Functions
    Functions::Range.register(env)
    Functions::Dict.register(env)
    Functions::Debug.register(env)
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

### 1. Create `src/std/` Structure ⏳ TODO
- Create directory structure
- Move existing builtin implementations to appropriate modules
- Each module exposes `self.register(env)` method

### 2. Update `Environment` ⏳ TODO
```crystal
def initialize(
  @override_builtins : Bool = false,
  load_std : Bool = true,
  # ... other params
)
  # ...
  Std.load_all(self) if load_std
end
```

### 3. Reorganize Fixtures ✅ COMPLETED
- ✅ Create subdirectories under `fixtures/`
- ✅ Move existing fixtures to appropriate subdirectories
- ✅ Update spec helpers to find fixtures in new locations
- ✅ Ensure all specs pass with new structure

### 4. Update Specs ✅ COMPLETED
- ✅ Update `fixtures_spec.cr` to handle subdirectories
- ✅ Add helper to glob fixtures from multiple directories
- ✅ Verify all snapshot tests still pass (185 tests)

### 5. Documentation ⏳ TODO
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
Crinkle::Std::Filters::Strings.register(env)
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
- [ ] Each module has `self.register(env)` method
- [ ] Environment supports `load_std` parameter (defaults to true)
- [x] Fixtures reorganized into logical subdirectories
- [x] All specs pass with new structure (185 tests)
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
- [ ] Create `src/std.cr` with `load_all` method
- [ ] Update `Environment` to support `load_std` parameter

### Fixture Reorganization
- [x] Create `fixtures/lexer/` and migrate lexer-focused fixtures (9 fixtures)
- [x] Create `fixtures/parser/` and migrate parser-focused fixtures (77 fixtures)
- [x] Create `fixtures/formatter/` and migrate formatter-focused fixtures (51 fixtures)
- [x] Create `fixtures/linter/` and migrate linter-focused fixtures (11 fixtures)
- [x] Create `fixtures/renderer/` and migrate renderer-focused fixtures (22 fixtures)
- [x] Create `fixtures/std_filters/` for filter tests (1 fixture)
- [x] Create `fixtures/std_tests/` for test tests (1 fixture)
- [x] Create `fixtures/std_functions/` for function tests (empty)
- [x] Create `fixtures/integration/` for end-to-end tests (6 fixtures)
- [x] Update spec helpers to find fixtures in new locations
- [x] Ensure all existing specs pass with new structure (185 tests passing)

### Documentation
- [ ] Update README with selective loading examples
- [ ] Update AGENTS.md with fixture organization
- [ ] Add examples of custom filter/test registration

## Implementation Details

### Fixture Reorganization (Completed)

**Changes Made:**

1. **Directory Structure Created:**
   - `fixtures/lexer/` - 9 token-level tests
   - `fixtures/parser/` - 77 AST construction tests
   - `fixtures/formatter/` - 51 formatting tests
   - `fixtures/linter/` - 11 linting tests (new category)
   - `fixtures/renderer/` - 22 execution tests
   - `fixtures/std_filters/` - 1 filter test
   - `fixtures/std_tests/` - 1 test test
   - `fixtures/std_functions/` - empty, ready for future tests
   - `fixtures/integration/` - 6 end-to-end tests
   - `fixtures/extensions/` - 6 extension tests (unchanged)

2. **Spec Helper Updates ([spec/spec_helper.cr](spec/spec_helper.cr)):**
   - Added `recursive` parameter to `fixture_templates()` for subdirectory discovery
   - Added `exclude` parameter to skip directories like `extensions/`
   - Updated template loaders to search recursively with `Dir.glob("fixtures/**/*.j2")`
   - Maintains backwards compatibility for non-recursive lookups

3. **Fixtures Spec Simplification ([spec/fixtures_spec.cr](spec/fixtures_spec.cr)):**
   - Reduced from 127 lines to 71 lines
   - Removed compile-time macros in favor of runtime iteration
   - Each fixture generates its own test case (185 total)
   - Separated main fixtures from extension fixtures with different environments
   - Simplified `run_fixture()` method with block parameter instead of proc

4. **Other Spec Updates:**
   - [spec/lexer_spec.cr](spec/lexer_spec.cr): Updated paths to `fixtures/lexer/`
   - [spec/parser_spec.cr](spec/parser_spec.cr): Updated paths to `fixtures/lexer/`

5. **Linter Detection:**
   - Updated to detect linter fixtures by directory path (`info.base_dir.includes?("linter")`)
   - Previously only checked filename prefix (`info.name.starts_with?("lint_")`)

**Benefits Achieved:**
- Clear separation of fixtures by pipeline stage
- Each test case is individually named and can be run in isolation
- Easier to find and understand what each fixture tests
- Better organization for adding future test categories
- All 185 tests passing

**Commit:** `10813f9` - "Reorganize fixtures into logical subdirectories"

### Standard Library (Not Yet Implemented)

The `src/std/` structure and selective loading remain to be implemented. Current builtins are still registered directly in test helpers and `Environment`.

## Out of Scope

- Implementing new filters/tests (covered in Phases 15-16)
- Performance optimization of builtin loading
- Dynamic plugin system for third-party extensions
- Packaging std library as separate shard

## Notes

This phase is foundational for Phases 14-19, which add new builtins and APIs. Having a clean standard library structure makes it easier to add and document new features.
