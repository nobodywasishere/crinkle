require "./value"
require "./arguments"

module Crinkle
  # Type alias for callable procs that take Arguments and return a Value.
  # Objects can return these from `jinja_call` to expose callable methods.
  #
  # Example:
  # ```
  # def jinja_call(name : String) : CallableProc?
  #   case name
  #   when "localize"
  #     ->(args : Arguments) : Value {
  #       key = args.varargs[0]?.try(&.to_s) || ""
  #       Crinkle.value("Localized: #{key}")
  #     }
  #   end
  # end
  # ```
  alias CallableProc = Arguments -> Value
end
