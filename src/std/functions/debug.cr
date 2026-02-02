module Crinkle::Std::Functions
  module Debug
    Crinkle.define_function :lipsum,
      params: {n: Int64, html: Bool, min: Int64},
      defaults: {n: 5_i64, html: true, min: 20_i64},
      returns: String,
      doc: "Generate lorem ipsum placeholder text" do |n, html, min|
      n_count = n.as?(Int64) || 5_i64
      html_mode = html.as?(Bool) || true
      min_words = min.as?(Int64) || 20_i64

      # Simple lorem ipsum generator
      words = [
        "lorem", "ipsum", "dolor", "sit", "amet", "consectetur",
        "adipiscing", "elit", "sed", "do", "eiusmod", "tempor",
        "incididunt", "ut", "labore", "et", "dolore", "magna",
        "aliqua", "enim", "ad", "minim", "veniam", "quis",
      ]

      paragraphs = Array(String).new
      n_count.times do
        word_count = min_words
        paragraph_words = Array(String).new
        word_count.times do |i|
          paragraph_words << words[i % words.size]
        end
        paragraph = paragraph_words.join(" ").capitalize + "."
        paragraphs << (html_mode ? "<p>#{paragraph}</p>" : paragraph)
      end

      paragraphs.join(html_mode ? "\n" : "\n\n")
    end

    Crinkle.define_function :cycler,
      returns: Array,
      doc: "Create a cycler object for cycling through values" do
      # Returns a cycler object (array with cycle state)
      # In a real implementation this would be a custom object
      # For now, return the array
      args
    end

    Crinkle.define_function :joiner,
      params: {sep: String},
      defaults: {sep: ", "},
      returns: String,
      doc: "Create a joiner object for joining output" do |sep|
      sep = ", " if sep.is_a?(Undefined) || sep.nil?
      # Returns a joiner object that returns empty on first call, then separator
      # For now, just return the separator
      sep.to_s
    end

    def self.register(env : Environment) : Nil
      register_function_lipsum(env)
      register_function_cycler(env)
      register_function_joiner(env)
    end
  end
end
