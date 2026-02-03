module Crinkle::Std
  # Load all standard library filters, tests, and functions into an environment
  def self.load_all(env : Environment) : Nil
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
    Functions::Macro.register(env)
  end
end
