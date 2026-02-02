module Crinkle::Std::Functions
  module Range
    def self.register(env : Environment) : Nil
      env.register_function("range") do |args, _kwargs, _ctx|
        case args.size
        when 1
          # range(n) -> 0...n
          stop = args[0].as?(Int64) || 0_i64
          (0_i64...stop).map { |i| i.as(Value) }.to_a
        when 2
          # range(start, stop) -> start...stop
          start = args[0].as?(Int64) || 0_i64
          stop = args[1].as?(Int64) || 0_i64
          (start...stop).map { |i| i.as(Value) }.to_a
        when 3
          # range(start, stop, step)
          start = args[0].as?(Int64) || 0_i64
          stop = args[1].as?(Int64) || 0_i64
          step = args[2].as?(Int64) || 1_i64

          result = Array(Value).new
          if step > 0
            current = start
            while current < stop
              result << current
              current += step
            end
          elsif step < 0
            current = start
            while current > stop
              result << current
              current += step
            end
          end
          result
        else
          Array(Value).new
        end
      end
    end
  end
end
