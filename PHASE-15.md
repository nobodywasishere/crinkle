# Phase 15 — Required Builtin Filters (Detailed Plan)

## Objectives
- Implement complete set of filters needed for production templates.
- Match Jinja2 filter semantics and signatures.
- Enable migration from existing Jinja2/Crinja templates.

## Priority
**HIGH**

## Motivation
Analysis of a real-world codebase with 328 Jinja2 templates identified these required filters:

| Filter | Uses | Status | Notes |
|--------|------|--------|-------|
| `safe` | 221 | **Missing** | Mark string as safe (no escaping) |
| `default` | 72 | Done | |
| `length` | 52 | Done | |
| `string` | 24 | **Missing** | Convert to string |
| `urlencode` | 20 | **Missing** | URL encode string |
| `join` | 14 | **Missing** | Join array with separator |
| `select` | 9 | **Missing** | Filter array by test |
| `int` | 9 | **Missing** | Convert to integer |
| `first` | 9 | **Missing** | First element of sequence |
| `replace` | 8 | **Missing** | String replacement |
| `e` | 5 | Done | Alias for `escape` |
| `tojson` | 4 | **Missing** | Convert to JSON |
| `capitalize` | 4 | **Missing** | Capitalize first character |
| `selectattr` | 3 | **Missing** | Filter by attribute test |
| `round` | 3 | **Missing** | Round number |
| `upper` | 2 | Done | |
| `random` | 2 | **Missing** | Random element from sequence |
| `urlize` | 1 | **Missing** | Convert URLs to clickable links |
| `truncate` | 1 | **Missing** | Truncate string |
| `map` | 1 | **Missing** | Apply filter/attribute to each element |
| `lower` | 1 | Done | |
| `format` | 1 | **Missing** | Printf-style formatting |

## Scope (Phase 15)
Implement 18 missing filters in `src/std/filters/` or `Environment#register_builtin_filters_tests`.

## Reference Implementations

### 1. safe — Mark string as safe (no escaping)
```crystal
@filters["safe"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Value do
  SafeString.new(value.to_s)
end
```

### 2. string — Convert to string
```crystal
@filters["string"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Value do
  value.to_s
end
```

### 3. urlencode — URL encode string
```crystal
@filters["urlencode"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Value do
  URI.encode_www_form(value.to_s)
end
```

### 4. join — Join array with separator
```crystal
@filters["join"] = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value do
  separator = kwargs["d"]? || args[0]? || ""
  case value
  when Array(Value)
    value.map(&.to_s).join(separator.to_s)
  else
    value.to_s
  end
end
```

### 5. select — Filter array by test
```crystal
@filters["select"] = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value do
  test_name = args[0]?.try(&.to_s)
  case value
  when Array(Value)
    if test_name && (test = @tests[test_name]?)
      value.select { |item| test.call(item, args[1..]? || Array(Value).new, kwargs) }
    else
      value.select { |item| truthy?(item) }
    end
  else
    value
  end
end
```

### 6. int — Convert to integer
```crystal
@filters["int"] = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value do
  default = kwargs["default"]? || args[0]? || 0_i64
  base = (kwargs["base"]? || args[1]?).try(&.to_s.to_i?) || 10
  case value
  when Number then value.to_i64
  when String then value.to_i64?(base) || default
  else default
  end
end
```

### 7. first — First element of sequence
```crystal
@filters["first"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Value do
  case value
  when Array(Value) then value.first? || Undefined.new("first")
  when String then value[0]?.try(&.to_s) || ""
  else Undefined.new("first")
  end
end
```

### 8. replace — String replacement
```crystal
@filters["replace"] = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value do
  old_str = kwargs["old"]? || args[0]?
  new_str = kwargs["new"]? || args[1]?
  count = (kwargs["count"]? || args[2]?).try(&.to_s.to_i?)
  return value unless old_str && new_str
  str = value.to_s
  count ? count.times { str = str.sub(old_str.to_s, new_str.to_s) }; str : str.gsub(old_str.to_s, new_str.to_s)
end
```

### 9. e — Alias for escape
```crystal
@filters["e"] = @filters["escape"]
```

### 10. tojson — Convert to JSON
```crystal
@filters["tojson"] = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value do
  indent = kwargs["indent"]?.try(&.to_s.to_i?)
  SafeString.new(value_to_json(value, indent))
end
```

### 11. capitalize — Capitalize first character
```crystal
@filters["capitalize"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Value do
  str = value.to_s
  return str if str.empty?
  str[0].upcase + str[1..]?.try(&.downcase) || ""
end
```

### 12. selectattr — Filter by attribute test
```crystal
@filters["selectattr"] = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value do
  attr_name = args[0]?.try(&.to_s) || return value
  test_name = args[1]?.try(&.to_s)
  case value
  when Array(Value)
    value.select do |item|
      attr_value = get_attribute(item, attr_name)
      test_name && (test = @tests[test_name]?) ? test.call(attr_value, args[2..]? || Array(Value).new, kwargs) : truthy?(attr_value)
    end
  else
    value
  end
end
```

### 13. round — Round number
```crystal
@filters["round"] = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value do
  precision = (kwargs["precision"]? || args[0]?).try(&.to_s.to_i?) || 0
  method = (kwargs["method"]? || args[1]?).try(&.to_s) || "common"
  num = value.is_a?(Number) ? value.to_f64 : return value
  case method
  when "ceil" then num.ceil(precision)
  when "floor" then num.floor(precision)
  else num.round(precision)
  end
end
```

### 14. random — Random element from sequence
```crystal
@filters["random"] = ->(value : Value, _args : Array(Value), _kwargs : Hash(String, Value)) : Value do
  case value
  when Array(Value) then value.sample? || Undefined.new("random")
  else value
  end
end
```

### 15. urlize — Convert URLs to clickable links
```crystal
@filters["urlize"] = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value do
  trim_url_limit = kwargs["trim_url_limit"]?.try(&.to_s.to_i?)
  nofollow = kwargs["nofollow"]?.try { |v| truthy?(v) } || false
  target = kwargs["target"]?.try(&.to_s)
  str = value.to_s
  url_regex = /https?:\/\/[^\s<>"]+/
  str.gsub(url_regex) do |url|
    display = trim_url_limit ? url[0, trim_url_limit] + "..." : url
    rel = nofollow ? %( rel="nofollow") : ""
    tgt = target ? %( target="#{target}") : ""
    %(<a href="#{url}"#{rel}#{tgt}>#{display}</a>)
  end
end
```

### 16. truncate — Truncate string
```crystal
@filters["truncate"] = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value do
  length = (kwargs["length"]? || args[0]?).try(&.to_s.to_i?) || 255
  killwords = kwargs["killwords"]?.try { |v| truthy?(v) } || false
  end_str = (kwargs["end"]? || args[2]?).try(&.to_s) || "..."
  leeway = (kwargs["leeway"]? || args[3]?).try(&.to_s.to_i?) || 0
  str = value.to_s
  return str if str.size <= length + leeway
  if killwords
    str[0, length - end_str.size] + end_str
  else
    truncated = str[0, length - end_str.size]
    (idx = truncated.rindex(' ')) ? truncated[0, idx] + end_str : truncated + end_str
  end
end
```

### 17. map — Apply filter/attribute to each element
```crystal
@filters["map"] = ->(value : Value, args : Array(Value), kwargs : Hash(String, Value)) : Value do
  case value
  when Array(Value)
    if attr = kwargs["attribute"]?.try(&.to_s)
      value.map { |item| get_attribute(item, attr) }
    elsif filter_name = args[0]?.try(&.to_s)
      (filter = @filters[filter_name]?) ? value.map { |item| filter.call(item, args[1..]? || Array(Value).new, kwargs) } : value
    else
      value
    end
  else
    value
  end
end
```

### 18. format — Printf-style formatting
```crystal
@filters["format"] = ->(value : Value, args : Array(Value), _kwargs : Hash(String, Value)) : Value do
  format_str = value.to_s
  format_args = args.map(&.to_s)
  sprintf(format_str, *format_args)
rescue
  value
end
```

## Test Fixtures
Create fixtures in `fixtures/std/filters/` for each filter with expected inputs/outputs.

## Acceptance Criteria
- All 18 filters implemented with correct Jinja2 semantics.
- Filters handle edge cases (empty arrays, nil values, type mismatches).
- Test fixtures pass for all filters.

## Checklist
- [ ] Add `safe` filter
- [ ] Add `string` filter
- [ ] Add `urlencode` filter
- [ ] Add `join` filter
- [ ] Add `select` filter
- [ ] Add `int` filter
- [ ] Add `first` filter
- [ ] Add `replace` filter
- [ ] Add `e` as alias for `escape`
- [ ] Add `tojson` filter
- [ ] Add `capitalize` filter
- [ ] Add `selectattr` filter
- [ ] Add `round` filter
- [ ] Add `random` filter
- [ ] Add `urlize` filter
- [ ] Add `truncate` filter
- [ ] Add `map` filter
- [ ] Add `format` filter
- [ ] Create test fixtures for each filter
