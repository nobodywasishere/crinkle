module Crinkle::Std::Functions
  module Debug
    def self.register(env : Environment) : Nil
      env.register_function("lipsum") do |args, kwargs, _ctx|
        n = args.first?.as?(Int64) || 5_i64
        html = kwargs["html"]?.as?(Bool) || true
        min_words = kwargs["min"]?.as?(Int64) || 20_i64

        # Simple lorem ipsum generator
        words = [
          "lorem", "ipsum", "dolor", "sit", "amet", "consectetur",
          "adipiscing", "elit", "sed", "do", "eiusmod", "tempor",
          "incididunt", "ut", "labore", "et", "dolore", "magna",
          "aliqua", "enim", "ad", "minim", "veniam", "quis",
        ]

        paragraphs = Array(String).new
        n.times do
          word_count = min_words
          paragraph_words = Array(String).new
          word_count.times do |i|
            paragraph_words << words[i % words.size]
          end
          paragraph = paragraph_words.join(" ").capitalize + "."
          paragraphs << (html ? "<p>#{paragraph}</p>" : paragraph)
        end

        paragraphs.join(html ? "\n" : "\n\n")
      end

      env.register_function("cycler") do |args, _kwargs, _ctx|
        # Returns a cycler object (array with cycle state)
        # In a real implementation this would be a custom object
        # For now, return the array
        args
      end

      env.register_function("joiner") do |args, _kwargs, _ctx|
        sep = args.first?.to_s || ", "
        # Returns a joiner object that returns empty on first call, then separator
        # For now, just return the separator
        sep
      end
    end
  end
end
