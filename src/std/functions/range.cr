module Crinkle::Std::Functions
  module Range
    Crinkle.define_function :range,
      params: {start: Int64, stop: Int64, step: Int64},
      defaults: {start: nil, stop: nil, step: 1_i64},
      returns: Array,
      doc: "Create a range of numbers" do |start, stop, step|
      # Handle variadic signature: range(stop), range(start, stop), or range(start, stop, step)
      start_val = start
      stop_val = stop
      step = step.as?(Int64) || 1_i64

      # Determine actual start and stop based on what was provided
      if start_val.is_a?(Undefined) || start_val.nil?
        # No arguments - return empty array
        Array(Value).new
      elsif stop_val.is_a?(Undefined) || stop_val.nil?
        # Only one argument: range(stop)
        actual_start = 0_i64
        actual_stop = start_val.as?(Int64) || 0_i64

        # Generate the range
        result = Array(Value).new
        if step > 0
          current = actual_start
          while current < actual_stop
            result << current
            current += step
          end
        elsif step < 0
          current = actual_start
          while current > actual_stop
            result << current
            current += step
          end
        end
        result
      else
        # Two or three arguments: range(start, stop) or range(start, stop, step)
        actual_start = start_val.as?(Int64) || 0_i64
        actual_stop = stop_val.as?(Int64) || 0_i64

        # Generate the range
        result = Array(Value).new
        if step > 0
          current = actual_start
          while current < actual_stop
            result << current
            current += step
          end
        elsif step < 0
          current = actual_start
          while current > actual_stop
            result << current
            current += step
          end
        end
        result
      end
    end

    def self.register(env : Environment) : Nil
      register_function_range(env)
    end
  end
end
