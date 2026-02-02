module Crinkle::Std::Filters
  module Html
    # Helper method for HTML escaping
    private def self.escape_html(value : Value) : Value
      if value.is_a?(SafeString)
        value
      else
        value.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub("\"", "&quot;")
          .gsub("'", "&#39;")
      end
    end

    Crinkle.define_filter :escape,
      params: {value: Any},
      returns: String,
      doc: "Escape HTML special characters" do |value|
      # Don't double-escape SafeString
      if value.is_a?(SafeString)
        value
      else
        value.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub("\"", "&quot;")
          .gsub("'", "&#39;")
      end
    end

    Crinkle.define_filter :e,
      params: {value: Any},
      returns: String,
      doc: "Alias for escape filter" do |value|
      # Don't double-escape SafeString
      if value.is_a?(SafeString)
        value
      else
        value.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub("\"", "&quot;")
          .gsub("'", "&#39;")
      end
    end

    Crinkle.define_filter :safe,
      params: {value: Any},
      returns: SafeString,
      doc: "Mark string as safe (no escaping)" do |value|
      SafeString.new(value.to_s)
    end

    Crinkle.define_filter :striptags,
      params: {value: String},
      returns: String,
      doc: "Remove HTML tags from string" do |value|
      value.to_s.gsub(/<[^>]*>/, "")
    end

    Crinkle.define_filter :urlize,
      params: {value: String, trim_url_limit: Int64, nofollow: Bool, target: String, rel: String},
      defaults: {trim_url_limit: nil, nofollow: false, target: "", rel: ""},
      returns: SafeString,
      doc: "Convert URLs in text to clickable links" do |value, trim_url_limit, nofollow, target, rel|
      trim_url_limit = trim_url_limit.as?(Int64)
      nofollow = nofollow.as?(Bool) || false
      target = target.to_s
      rel = rel.to_s

      str = value.to_s
      url_pattern = /(https?:\/\/[^\s<>"{}|\\^`[\]]+)/

      result = str.gsub(url_pattern) do |match|
        url = match.to_s
        display_url = if trim_url_limit && url.size > trim_url_limit
                        url[0...trim_url_limit.to_i] + "..."
                      else
                        url
                      end

        attrs = ["href=\"#{url}\""]
        attrs << "rel=\"nofollow\"" if nofollow
        attrs << "target=\"#{target}\"" unless target.empty?
        attrs << "rel=\"#{rel}\"" if !rel.empty? && !nofollow

        "<a #{attrs.join(" ")}>#{display_url}</a>"
      end

      SafeString.new(result)
    end

    Crinkle.define_filter :urlencode,
      params: {value: String},
      returns: String,
      doc: "URL encode a string" do |value|
      URI.encode_www_form(value.to_s)
    end

    def self.register(env : Environment) : Nil
      register_filter_escape(env)
      register_filter_e(env)
      register_filter_safe(env)
      register_filter_striptags(env)
      register_filter_urlize(env)
      register_filter_urlencode(env)
    end
  end
end
