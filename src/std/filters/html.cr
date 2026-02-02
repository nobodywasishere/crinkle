module Crinkle::Std::Filters
  module Html
    def self.register(env : Environment) : Nil
      env.register_filter("escape") do |value, _args, _kwargs, _ctx|
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

      env.register_filter("e") do |value, _args, _kwargs, _ctx|
        # Alias for escape
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

      env.register_filter("safe") do |value, _args, _kwargs, _ctx|
        SafeString.new(value.to_s)
      end

      env.register_filter("striptags") do |value, _args, _kwargs, _ctx|
        value.to_s.gsub(/<[^>]*>/, "")
      end

      env.register_filter("urlize") do |value, args, kwargs, _ctx|
        trim_url_limit = args.first?.as?(Int64)
        nofollow = kwargs["nofollow"]?.as?(Bool) || false
        target = kwargs["target"]?.to_s
        rel = kwargs["rel"]?.to_s

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
          attrs << "target=\"#{target}\"" if target
          attrs << "rel=\"#{rel}\"" if rel && !nofollow

          "<a #{attrs.join(" ")}>#{display_url}</a>"
        end

        SafeString.new(result)
      end

      env.register_filter("urlencode") do |value, _args, _kwargs, _ctx|
        URI.encode_www_form(value.to_s)
      end
    end
  end
end
