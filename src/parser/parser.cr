module Crinkle
  class Parser
    private alias BuiltInTagHandler = Proc(Span, Bool, AST::Node?)

    private struct EndTagInfo
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool

      def initialize(@span : Span, @trim_left : Bool, @trim_right : Bool) : Nil
      end
    end

    private struct TagInfo
      getter span : Span
      getter? trim_left : Bool
      getter? trim_right : Bool

      def initialize(@span : Span, @trim_left : Bool, @trim_right : Bool) : Nil
      end
    end

    getter diagnostics : Array(Diagnostic)

    def initialize(tokens : Array(Token), environment : Environment = Environment.new) : Nil
      @tokens = tokens
      @index = 0
      @diagnostics = Array(Diagnostic).new
      @environment = environment
      @last_block_end_trim_right = false
    end

    def parse : AST::Template
      nodes = Array(AST::Node).new

      while !at_end?
        case current.type
        when TokenType::Text
          nodes << AST::Text.new(current.lexeme, current.span)
          advance
        when TokenType::Comment
          nodes << parse_comment
        when TokenType::VarStart
          nodes << parse_output
        when TokenType::BlockStart
          node = parse_block
          nodes << node if node
        when TokenType::EOF
          break
        else
          emit_unexpected_token("template")
          advance
        end
      end

      AST::Template.new(nodes, template_span(nodes))
    end

    private def parse_output : AST::Output
      start_token = current
      start_span = start_token.span
      trim_left = trim_left_from_start(start_token)
      advance
      skip_whitespace

      expr = parse_expression([TokenType::VarEnd])
      skip_whitespace

      trim_right = false
      end_span = if current.type == TokenType::VarEnd
                   trim_right = trim_right_from_end(current)
                   token = advance
                   token.span
                 else
                   emit_expected_token("Expected '}}' to close expression.")
                   recover_to([TokenType::VarEnd])
                   if current.type == TokenType::VarEnd
                     trim_right = trim_right_from_end(current)
                     token = advance
                     token.span
                   else
                     previous.span
                   end
                 end

      AST::Output.new(expr, span_between(start_span, end_span), trim_left, trim_right)
    end

    private def parse_comment : AST::Comment
      token = current
      lexeme = token.lexeme
      trim_left = lexeme.starts_with?("{#-")
      trim_right = lexeme.ends_with?("-#}")
      content_start = trim_left ? 3 : 2
      content_end = trim_right ? 3 : 2
      text = if lexeme.size >= content_start + content_end
               lexeme[content_start, lexeme.size - content_start - content_end]
             else
               ""
             end
      advance
      AST::Comment.new(text, token.span, trim_left, trim_right)
    end

    private def parse_block : AST::Node?
      start_token = current
      start_span = start_token.span
      start_trim_left = trim_left_from_start(start_token)
      advance
      skip_whitespace

      unless current.type == TokenType::Identifier
        emit_expected_token("Expected block tag name after '{%'.")
        recover_to([TokenType::BlockEnd])
        advance if current.type == TokenType::BlockEnd
        return
      end

      tag_token = current
      tag = tag_token.lexeme
      advance

      if handler = tag_handlers[tag]?
        extension = @environment.tag_extension(tag)
        if extension && @environment.override_builtins? && extension.override?
          return handle_extension(tag, extension, start_span, start_trim_left)
        end
        return handler.call(start_span, start_trim_left)
      end

      if extension = @environment.tag_extension(tag)
        return handle_extension(tag, extension, start_span, start_trim_left)
      end

      # TODO(margret): Disabling to support custom tags without errors
      # emit_diagnostic(DiagnosticType::UnknownTag, "Unknown tag '#{tag}'.")
      parse_unknown_tag(tag, start_span, start_trim_left)
    end

    private def handle_extension(tag : String, extension : TagExtension, start_span : Span, start_trim_left : Bool) : AST::Node?
      node = extension.handler.call(self, start_span)
      return node if node
      return if extension.end_tags.empty?

      start_trim_right = @last_block_end_trim_right
      body, end_info, _end_tag = parse_until_any_end_tag(extension.end_tags, allow_end_name: true)
      end_info ||= EndTagInfo.new(start_span, false, false)

      AST::CustomTag.new(
        tag,
        Array(AST::Expr).new,
        Array(AST::KeywordArg).new,
        body,
        span_between(start_span, end_info.span),
        start_trim_left,
        start_trim_right,
        end_info.trim_left?,
        end_info.trim_right?
      )
    end

    private def parse_if(start_span : Span, start_trim_left : Bool) : AST::If
      skip_whitespace
      test = parse_expression([TokenType::BlockEnd])
      skip_whitespace

      if current.type == TokenType::BlockEnd
        @last_block_end_trim_right = trim_right_from_end(current)
        advance
      else
        emit_expected_token("Expected '%}' to close if tag.")
        recover_to([TokenType::BlockEnd])
        if current.type == TokenType::BlockEnd
          @last_block_end_trim_right = trim_right_from_end(current)
          advance
        end
      end

      start_trim_right = @last_block_end_trim_right
      body, hit_tag = parse_until_any_end_tag_peek(["endif", "else", "elif"])
      else_body = Array(AST::Node).new
      else_trim_left = false
      else_trim_right = false
      end_trim_left = false
      end_trim_right = false
      end_span = start_span

      case hit_tag
      when "else"
        else_info = consume_block_tag("else")
        else_trim_left = else_info.trim_left?
        else_trim_right = else_info.trim_right?
        else_body, end_info = parse_until_end_tag("endif")
        if end_info
          end_trim_left = end_info.trim_left?
          end_trim_right = end_info.trim_right?
          end_span = end_info.span
        end
      when "elif"
        elif_node = parse_elif
        else_body = [elif_node] of AST::Node
        end_trim_left = elif_node.end_trim_left?
        end_trim_right = elif_node.end_trim_right?
        end_span = elif_node.span
      when "endif"
        end_info = consume_end_tag
        end_trim_left = end_info.trim_left?
        end_trim_right = end_info.trim_right?
        end_span = end_info.span
      end

      end_span ||= start_span
      AST::If.new(
        test,
        body,
        else_body,
        span_between(start_span, end_span),
        start_trim_left,
        start_trim_right,
        else_trim_left,
        else_trim_right,
        end_trim_left,
        end_trim_right,
        false
      )
    end

    private def parse_for(start_span : Span, start_trim_left : Bool) : AST::For
      skip_whitespace

      target = parse_assignment_target("Expected loop variable name after 'for'.")

      skip_whitespace

      if current.type == TokenType::Identifier && current.lexeme == "in"
        advance
      else
        emit_expected_token("Expected 'in' in for loop.")
      end

      skip_whitespace
      iter = parse_expression([TokenType::BlockEnd])
      skip_whitespace

      if current.type == TokenType::BlockEnd
        @last_block_end_trim_right = trim_right_from_end(current)
        advance
      else
        emit_expected_token("Expected '%}' to close for tag.")
        recover_to([TokenType::BlockEnd])
        if current.type == TokenType::BlockEnd
          @last_block_end_trim_right = trim_right_from_end(current)
          advance
        end
      end

      start_trim_right = @last_block_end_trim_right
      body, hit_tag = parse_until_any_end_tag_peek(["endfor", "else"])
      else_body = Array(AST::Node).new
      else_trim_left = false
      else_trim_right = false
      end_trim_left = false
      end_trim_right = false
      end_span = start_span

      if hit_tag == "else"
        else_info = consume_block_tag("else")
        else_trim_left = else_info.trim_left?
        else_trim_right = else_info.trim_right?
        else_body, end_info = parse_until_end_tag("endfor")
        if end_info
          end_trim_left = end_info.trim_left?
          end_trim_right = end_info.trim_right?
          end_span = end_info.span
        end
      elsif hit_tag == "endfor"
        end_info = consume_end_tag
        end_trim_left = end_info.trim_left?
        end_trim_right = end_info.trim_right?
        end_span = end_info.span
      end

      end_span ||= start_span
      AST::For.new(
        target,
        iter,
        body,
        else_body,
        span_between(start_span, end_span),
        start_trim_left,
        start_trim_right,
        else_trim_left,
        else_trim_right,
        end_trim_left,
        end_trim_right
      )
    end

    private def parse_set(start_span : Span, start_trim_left : Bool) : AST::Node
      skip_whitespace
      target = parse_assignment_target("Expected variable name after 'set'.")
      skip_whitespace

      if operator?("=")
        advance
        skip_whitespace
        value = parse_expression([TokenType::BlockEnd])
        skip_whitespace
        end_span = expect_block_end("Expected '%}' to close set tag.")
        start_trim_right = @last_block_end_trim_right
        return AST::Set.new(
          target,
          value,
          span_between(start_span, end_span),
          start_trim_left,
          start_trim_right
        )
      end

      end_span = expect_block_end("Expected '%}' to close set tag.")
      start_trim_right = @last_block_end_trim_right
      body, end_info = parse_until_end_tag("endset")
      end_info ||= EndTagInfo.new(end_span, false, false)
      AST::SetBlock.new(
        target,
        body,
        span_between(start_span, end_info.span),
        start_trim_left,
        start_trim_right,
        end_info.trim_left?,
        end_info.trim_right?
      )
    end

    private def parse_block_tag(start_span : Span, start_trim_left : Bool) : AST::Block
      skip_whitespace
      name = parse_name("Expected block name after 'block'.")
      skip_whitespace
      end_span = expect_block_end("Expected '%}' to close block tag.")
      start_trim_right = @last_block_end_trim_right
      body, end_info = parse_until_end_tag("endblock", allow_end_name: true)
      end_info ||= EndTagInfo.new(end_span, false, false)
      AST::Block.new(
        name,
        body,
        span_between(start_span, end_info.span),
        start_trim_left,
        start_trim_right,
        end_info.trim_left?,
        end_info.trim_right?
      )
    end

    private def parse_extends(start_span : Span, start_trim_left : Bool) : AST::Extends
      skip_whitespace
      template = parse_expression([TokenType::BlockEnd])
      skip_whitespace
      end_span = expect_block_end("Expected '%}' to close extends tag.")
      start_trim_right = @last_block_end_trim_right
      AST::Extends.new(template, span_between(start_span, end_span), start_trim_left, start_trim_right)
    end

    private def parse_include(start_span : Span, start_trim_left : Bool) : AST::Include
      skip_whitespace
      template = parse_expression([TokenType::BlockEnd])
      with_context = true
      ignore_missing = false

      loop do
        skip_whitespace
        break if current.type == TokenType::BlockEnd
        if keyword?("ignore")
          advance
          skip_whitespace
          if keyword?("missing")
            advance
          else
            emit_expected_token("Expected 'missing' after 'ignore'.")
          end
          ignore_missing = true
          next
        end

        if keyword?("with")
          advance
          skip_whitespace
          if keyword?("context")
            advance
          else
            emit_expected_token("Expected 'context' after 'with'.")
          end
          with_context = true
          next
        end

        if keyword?("without")
          advance
          skip_whitespace
          if keyword?("context")
            advance
          else
            emit_expected_token("Expected 'context' after 'without'.")
          end
          with_context = false
          next
        end

        emit_unexpected_token("include tag")
        advance
      end

      end_span = expect_block_end("Expected '%}' to close include tag.")
      start_trim_right = @last_block_end_trim_right
      AST::Include.new(
        template,
        with_context,
        ignore_missing,
        span_between(start_span, end_span),
        start_trim_left,
        start_trim_right
      )
    end

    private def parse_import(start_span : Span, start_trim_left : Bool) : AST::Import
      skip_whitespace
      template = parse_expression([TokenType::BlockEnd])
      skip_whitespace

      alias_name = nil
      if keyword?("as")
        advance
        skip_whitespace
        alias_name = parse_name("Expected alias after 'as'.")
        # NOTE(margret): `as` is optional for crinja, copying that behaviour
        # else
        #   emit_expected_token("Expected 'as' after import target.")
      end

      skip_whitespace
      end_span = expect_block_end("Expected '%}' to close import tag.")
      start_trim_right = @last_block_end_trim_right
      AST::Import.new(template, alias_name, span_between(start_span, end_span), start_trim_left, start_trim_right)
    end

    private def parse_from(start_span : Span, start_trim_left : Bool) : AST::FromImport
      skip_whitespace
      template = parse_expression([TokenType::BlockEnd])
      skip_whitespace

      if keyword?("import")
        advance
      else
        emit_expected_token("Expected 'import' after from target.")
      end

      names = parse_import_names
      with_context = true

      loop do
        skip_whitespace
        break if current.type == TokenType::BlockEnd
        if keyword?("with")
          advance
          skip_whitespace
          if keyword?("context")
            advance
          else
            emit_expected_token("Expected 'context' after 'with'.")
          end
          with_context = true
          next
        end

        if keyword?("without")
          advance
          skip_whitespace
          if keyword?("context")
            advance
          else
            emit_expected_token("Expected 'context' after 'without'.")
          end
          with_context = false
          next
        end

        emit_unexpected_token("from import tag")
        advance
      end

      end_span = expect_block_end("Expected '%}' to close from import tag.")
      start_trim_right = @last_block_end_trim_right
      AST::FromImport.new(
        template,
        names,
        with_context,
        span_between(start_span, end_span),
        start_trim_left,
        start_trim_right
      )
    end

    private def parse_macro(start_span : Span, start_trim_left : Bool) : AST::Macro
      skip_whitespace
      name = parse_name("Expected macro name after 'macro'.")
      params = parse_macro_params
      skip_whitespace
      end_span = expect_block_end("Expected '%}' to close macro tag.")
      start_trim_right = @last_block_end_trim_right
      body, end_info = parse_until_end_tag("endmacro", allow_end_name: true)
      end_info ||= EndTagInfo.new(end_span, false, false)
      AST::Macro.new(
        name,
        params,
        body,
        span_between(start_span, end_info.span),
        start_trim_left,
        start_trim_right,
        end_info.trim_left?,
        end_info.trim_right?
      )
    end

    private def parse_call_block(start_span : Span, start_trim_left : Bool) : AST::CallBlock
      skip_whitespace
      call_args = nil
      call_kwargs = nil
      if punct?("(")
        args, kwargs, _end_span = parse_call_args([TokenType::BlockEnd], Array(String).new)
        call_args = args
        call_kwargs = kwargs
        skip_whitespace
      end

      expr = parse_expression([TokenType::BlockEnd])
      skip_whitespace
      end_span = expect_block_end("Expected '%}' to close call tag.")
      start_trim_right = @last_block_end_trim_right
      body, end_info = parse_until_end_tag("endcall", allow_end_name: true)
      end_info ||= EndTagInfo.new(end_span, false, false)

      callee = expr
      args = Array(AST::Expr).new
      kwargs = Array(AST::KeywordArg).new

      if expr.is_a?(AST::Call)
        callee = expr.callee
        args = expr.args
        kwargs = expr.kwargs
      end

      AST::CallBlock.new(
        callee,
        args,
        kwargs,
        body,
        span_between(start_span, end_info.span),
        call_args,
        call_kwargs,
        start_trim_left,
        start_trim_right,
        end_info.trim_left?,
        end_info.trim_right?
      )
    end

    private def parse_raw_block(start_span : Span, start_trim_left : Bool) : AST::Raw
      skip_whitespace
      expect_block_end("Expected '%}' to close raw tag.")
      start_trim_right = @last_block_end_trim_right

      tokens = Array(Token).new
      content_start = nil
      content_end = nil

      while !at_end?
        if current.type == TokenType::BlockStart && peek_block_tag == "endraw"
          end_info = consume_end_tag
          text = tokens.map(&.lexeme).join
          if content_start && content_end
            return AST::Raw.new(
              text,
              span_between(content_start, content_end),
              start_trim_left,
              start_trim_right,
              end_info.trim_left?,
              end_info.trim_right?
            )
          end
          return AST::Raw.new(
            text,
            span_between(start_span, end_info.span),
            start_trim_left,
            start_trim_right,
            end_info.trim_left?,
            end_info.trim_right?
          )
        end

        content_start ||= current.span
        content_end = current.span
        tokens << current
        advance
      end

      emit_diagnostic(DiagnosticType::MissingEndTag, "Missing end tag 'endraw'.")
      AST::Raw.new(tokens.map(&.lexeme).join, start_span, start_trim_left, start_trim_right)
    end

    private def parse_unknown_tag(tag : String, start_span : Span, start_trim_left : Bool) : AST::CustomTag
      skip_whitespace
      args = Array(AST::Expr).new
      kwargs = Array(AST::KeywordArg).new

      while current.type != TokenType::BlockEnd && !at_end?
        if keyword_arg_start?
          name = current.lexeme
          name_span = current.span
          advance
          skip_whitespace
          if operator?("=")
            advance
          else
            emit_expected_token("Expected '=' for keyword argument.")
          end
          skip_whitespace
          value = parse_expression([TokenType::BlockEnd])
          kwargs << AST::KeywordArg.new(name, value, span_between(name_span, value.span))
        else
          args << parse_expression([TokenType::BlockEnd])
        end
        skip_whitespace
      end

      end_span = expect_block_end("Expected '%}' to close #{tag} tag.")
      start_trim_right = @last_block_end_trim_right

      end_tag = "end#{tag}"
      if has_end_tag_ahead?(end_tag)
        body, end_info = parse_until_end_tag(end_tag, allow_end_name: true)
        end_info ||= EndTagInfo.new(end_span, false, false)
        return AST::CustomTag.new(
          tag,
          args,
          kwargs,
          body,
          span_between(start_span, end_info.span),
          start_trim_left,
          start_trim_right,
          end_info.trim_left?,
          end_info.trim_right?
        )
      end

      AST::CustomTag.new(
        tag,
        args,
        kwargs,
        Array(AST::Node).new,
        span_between(start_span, end_span),
        start_trim_left,
        start_trim_right
      )
    end

    private def tag_handlers : Hash(String, BuiltInTagHandler)
      @tag_handlers ||= {
        "if"       => ->(span : Span, trim_left : Bool) : AST::Node? { parse_if(span, trim_left) },
        "for"      => ->(span : Span, trim_left : Bool) : AST::Node? { parse_for(span, trim_left) },
        "set"      => ->(span : Span, trim_left : Bool) : AST::Node? { parse_set(span, trim_left) },
        "block"    => ->(span : Span, trim_left : Bool) : AST::Node? { parse_block_tag(span, trim_left) },
        "extends"  => ->(span : Span, trim_left : Bool) : AST::Node? { parse_extends(span, trim_left) },
        "include"  => ->(span : Span, trim_left : Bool) : AST::Node? { parse_include(span, trim_left) },
        "import"   => ->(span : Span, trim_left : Bool) : AST::Node? { parse_import(span, trim_left) },
        "from"     => ->(span : Span, trim_left : Bool) : AST::Node? { parse_from(span, trim_left) },
        "macro"    => ->(span : Span, trim_left : Bool) : AST::Node? { parse_macro(span, trim_left) },
        "call"     => ->(span : Span, trim_left : Bool) : AST::Node? { parse_call_block(span, trim_left) },
        "raw"      => ->(span : Span, trim_left : Bool) : AST::Node? { parse_raw_block(span, trim_left) },
        "endif"    => ->(_span : Span, _trim_left : Bool) : AST::Node? { parse_unexpected_end_tag("endif") },
        "endfor"   => ->(_span : Span, _trim_left : Bool) : AST::Node? { parse_unexpected_end_tag("endfor") },
        "endset"   => ->(_span : Span, _trim_left : Bool) : AST::Node? { parse_unexpected_end_tag("endset") },
        "endblock" => ->(_span : Span, _trim_left : Bool) : AST::Node? { parse_unexpected_end_tag("endblock") },
        "endmacro" => ->(_span : Span, _trim_left : Bool) : AST::Node? { parse_unexpected_end_tag("endmacro") },
        "endcall"  => ->(_span : Span, _trim_left : Bool) : AST::Node? { parse_unexpected_end_tag("endcall") },
        "endraw"   => ->(_span : Span, _trim_left : Bool) : AST::Node? { parse_unexpected_end_tag("endraw") },
      } of String => BuiltInTagHandler
    end

    private def parse_unexpected_end_tag(tag : String) : Nil
      emit_diagnostic(DiagnosticType::UnexpectedEndTag, "Unexpected '#{tag}'.")
      recover_to([TokenType::BlockEnd])
      advance if current.type == TokenType::BlockEnd
    end

    def parse_until_end_tag(end_tag : String, allow_end_name : Bool = false) : {Array(AST::Node), EndTagInfo?}
      nodes = Array(AST::Node).new

      while !at_end?
        if current.type == TokenType::BlockStart
          tag = peek_block_tag
          if tag == end_tag
            end_info = consume_end_tag(allow_end_name)
            return {nodes, end_info}
          end

          node = parse_block
          nodes << node if node
          next
        end

        case current.type
        when TokenType::Text
          nodes << AST::Text.new(current.lexeme, current.span)
          advance
        when TokenType::Comment
          nodes << parse_comment
        when TokenType::VarStart
          nodes << parse_output
        when TokenType::EOF
          break
        else
          emit_unexpected_token("block body")
          advance
        end
      end

      emit_diagnostic(DiagnosticType::MissingEndTag, "Missing end tag '#{end_tag}'.")
      {nodes, nil}
    end

    def parse_until_any_end_tag(
      end_tags : Array(String),
      allow_end_name : Bool = false,
    ) : {Array(AST::Node), EndTagInfo?, String?}
      nodes = Array(AST::Node).new

      while !at_end?
        if current.type == TokenType::BlockStart
          tag = peek_block_tag
          if tag && end_tags.includes?(tag)
            end_info = consume_end_tag(allow_end_name)
            return {nodes, end_info, tag}
          end

          node = parse_block
          nodes << node if node
          next
        end

        case current.type
        when TokenType::Text
          nodes << AST::Text.new(current.lexeme, current.span)
          advance
        when TokenType::Comment
          nodes << parse_comment
        when TokenType::VarStart
          nodes << parse_output
        when TokenType::EOF
          break
        else
          emit_unexpected_token("block body")
          advance
        end
      end

      unless end_tags.empty?
        message = if end_tags.size == 1
                    "Missing end tag '#{end_tags.first}'."
                  else
                    "Missing end tag (one of: #{end_tags.join(", ")})."
                  end
        emit_diagnostic(DiagnosticType::MissingEndTag, message)
      end

      {nodes, nil, nil}
    end

    private def parse_until_any_end_tag_peek(end_tags : Array(String)) : {Array(AST::Node), String?}
      nodes = Array(AST::Node).new

      while !at_end?
        if current.type == TokenType::BlockStart
          tag = peek_block_tag
          return {nodes, tag} if tag && end_tags.includes?(tag)

          node = parse_block
          nodes << node if node
          next
        end

        case current.type
        when TokenType::Text
          nodes << AST::Text.new(current.lexeme, current.span)
          advance
        when TokenType::Comment
          nodes << parse_comment
        when TokenType::VarStart
          nodes << parse_output
        when TokenType::EOF
          break
        else
          emit_unexpected_token("block body")
          advance
        end
      end

      unless end_tags.empty?
        message = if end_tags.size == 1
                    "Missing end tag '#{end_tags.first}'."
                  else
                    "Missing end tag (one of: #{end_tags.join(", ")})."
                  end
        emit_diagnostic(DiagnosticType::MissingEndTag, message)
      end

      {nodes, nil}
    end

    private def consume_block_tag(expected : String) : TagInfo
      start_token = current
      start_span = start_token.span
      trim_left = trim_left_from_start(start_token)
      advance
      skip_whitespace
      if current.type == TokenType::Identifier && current.lexeme == expected
        advance
      else
        emit_expected_token("Expected '#{expected}'.")
      end
      skip_whitespace
      end_span = expect_block_end("Expected '%}' to close #{expected} tag.")
      trim_right = @last_block_end_trim_right
      TagInfo.new(span_between(start_span, end_span), trim_left, trim_right)
    end

    private def parse_elif : AST::If
      start_token = current
      start_span = start_token.span
      start_trim_left = trim_left_from_start(start_token)
      advance
      skip_whitespace
      if current.type == TokenType::Identifier && current.lexeme == "elif"
        advance
      else
        emit_expected_token("Expected 'elif'.")
      end
      skip_whitespace
      test = parse_expression([TokenType::BlockEnd])
      skip_whitespace
      expect_block_end("Expected '%}' to close elif tag.")
      start_trim_right = @last_block_end_trim_right

      body, hit_tag = parse_until_any_end_tag_peek(["endif", "else", "elif"])
      else_body = Array(AST::Node).new
      else_trim_left = false
      else_trim_right = false
      end_trim_left = false
      end_trim_right = false
      end_span = start_span

      case hit_tag
      when "else"
        else_info = consume_block_tag("else")
        else_trim_left = else_info.trim_left?
        else_trim_right = else_info.trim_right?
        else_body, end_info = parse_until_end_tag("endif")
        if end_info
          end_trim_left = end_info.trim_left?
          end_trim_right = end_info.trim_right?
          end_span = end_info.span
        end
      when "elif"
        elif_node = parse_elif
        else_body = [elif_node] of AST::Node
        end_span = elif_node.span
      when "endif"
        end_info = consume_end_tag
        end_trim_left = end_info.trim_left?
        end_trim_right = end_info.trim_right?
        end_span = end_info.span
      end

      end_span ||= start_span
      AST::If.new(
        test,
        body,
        else_body,
        span_between(start_span, end_span),
        start_trim_left,
        start_trim_right,
        else_trim_left,
        else_trim_right,
        end_trim_left,
        end_trim_right,
        true
      )
    end

    private def parse_assignment_target(message : String) : AST::Target
      targets = Array(AST::Expr).new
      loop do
        targets << parse_target_atom(message)
        skip_whitespace
        break unless punct?(",")
        advance
        skip_whitespace
      end

      if targets.size == 1
        target = targets.first
        return target.as(AST::Target) if target.is_a?(AST::Target)
        emit_expected_token(message)
        return AST::Name.new("", current.span)
      end

      items = targets.select(AST::Target)
      if items.size != targets.size
        emit_expected_token(message)
      end
      start_span = targets.first.span
      end_span = targets.last.span
      expr_items = items.map { |item| item.as(AST::Expr) }
      AST::TupleLiteral.new(expr_items, span_between(start_span, end_span))
    end

    private def parse_target_atom(message : String) : AST::Expr
      unless current.type == TokenType::Identifier
        emit_expected_token(message)
        return AST::Name.new("", current.span)
      end

      target = AST::Name.new(current.lexeme, current.span)
      advance

      loop do
        skip_whitespace
        if punct?(".")
          start_span = target.span
          advance
          if current.type == TokenType::Identifier
            name = current.lexeme
            end_span = current.span
            advance
            target = AST::GetAttr.new(target, name, span_between(start_span, end_span))
          else
            emit_expected_token("Expected attribute name after '.'.")
          end
          next
        end

        if punct?("[")
          start_span = target.span
          advance
          index = parse_expression([TokenType::Punct], ["]"])
          skip_whitespace
          end_span = index.span
          if punct?("]")
            end_span = current.span
            advance
          else
            emit_expected_token("Expected ']' to close index.")
          end
          target = AST::GetItem.new(target, index, span_between(start_span, end_span))
          next
        end

        break
      end

      target
    end

    private def parse_name(message : String) : String
      if current.type == TokenType::Identifier
        name = current.lexeme
        advance
        name
      else
        emit_expected_token(message)
        ""
      end
    end

    private def parse_import_names : Array(AST::ImportName)
      names = Array(AST::ImportName).new
      loop do
        skip_whitespace
        if current.type == TokenType::BlockEnd
          emit_expected_token("Expected name in import list.") if names.empty?
          break
        end

        if current.type != TokenType::Identifier
          emit_expected_token("Expected name in import list.")
          break
        end

        name = current.lexeme
        name_span = current.span
        advance
        skip_whitespace

        alias_name = nil
        alias_span = name_span
        if keyword?("as")
          advance
          skip_whitespace
          if current.type == TokenType::Identifier
            alias_name = current.lexeme
            alias_span = current.span
            advance
          else
            emit_expected_token("Expected alias after 'as'.")
          end
        end

        names << AST::ImportName.new(name, alias_name, span_between(name_span, alias_span))
        skip_whitespace
        break unless punct?(",")
        advance
        skip_whitespace
      end
      names
    end

    private def parse_macro_params : Array(AST::MacroParam)
      params = Array(AST::MacroParam).new
      skip_whitespace
      return params unless punct?("(")

      advance
      skip_whitespace
      if punct?(")")
        advance
        return params
      end

      loop do
        skip_whitespace
        if current.type != TokenType::Identifier
          emit_expected_token("Expected parameter name in macro.")
          break
        end

        name = current.lexeme
        name_span = current.span
        advance
        skip_whitespace

        default_value = nil
        end_span = name_span
        if operator?("=")
          advance
          skip_whitespace
          default_value = parse_expression([TokenType::Punct], [",", ")"])
          end_span = default_value.span
        end

        params << AST::MacroParam.new(name, default_value, span_between(name_span, end_span))
        skip_whitespace
        break unless punct?(",")
        advance
        skip_whitespace
        break if punct?(")")
      end

      if punct?(")")
        advance
      else
        emit_expected_token("Expected ')' to close macro parameters.")
      end

      params
    end

    def expect_block_end(message : String) : Span
      if current.type == TokenType::BlockEnd
        @last_block_end_trim_right = trim_right_from_end(current)
        end_span = current.span
        advance
        return end_span
      end

      emit_expected_token(message)
      recover_to([TokenType::BlockEnd])
      if current.type == TokenType::BlockEnd
        @last_block_end_trim_right = trim_right_from_end(current)
        end_span = current.span
        advance
        return end_span
      end

      previous.span
    end

    private def consume_end_tag(allow_name : Bool = false) : EndTagInfo
      start_span = current.span
      trim_left = trim_left_from_start(current)
      advance
      skip_whitespace
      if current.type == TokenType::Identifier
        advance
      else
        emit_expected_token("Expected end tag name.")
      end
      skip_whitespace
      if allow_name && current.type == TokenType::Identifier
        advance
        skip_whitespace
      end
      if current.type == TokenType::BlockEnd
        trim_right = trim_right_from_end(current)
        end_span = current.span
        advance
        EndTagInfo.new(span_between(start_span, end_span), trim_left, trim_right)
      else
        emit_expected_token("Expected '%}' to close end tag.")
        EndTagInfo.new(start_span, trim_left, false)
      end
    end

    def parse_expression(stop_types : Array(TokenType), stop_lexemes : Array(String) = Array(String).new) : AST::Expr
      skip_whitespace
      if stop_at?(stop_types, stop_lexemes)
        emit_diagnostic(DiagnosticType::ExpectedExpression, "Expected expression.")
        return AST::Literal.new(nil, current.span)
      end

      parse_or(stop_types, stop_lexemes)
    end

    private def parse_or(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      left = parse_and(stop_types, stop_lexemes)

      loop do
        skip_whitespace
        break if stop_at?(stop_types, stop_lexemes)
        break unless keyword?("or")
        advance
        right = parse_and(stop_types, stop_lexemes)
        left = AST::Binary.new("or", left, right, span_between(left.span, right.span))
      end

      left
    end

    private def parse_and(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      left = parse_not(stop_types, stop_lexemes)

      loop do
        skip_whitespace
        break if stop_at?(stop_types, stop_lexemes)
        break unless keyword?("and")
        advance
        right = parse_not(stop_types, stop_lexemes)
        left = AST::Binary.new("and", left, right, span_between(left.span, right.span))
      end

      left
    end

    private def parse_not(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      skip_whitespace
      if keyword?("not")
        start_span = current.span
        advance
        expr = parse_not(stop_types, stop_lexemes)
        return AST::Unary.new("not", expr, span_between(start_span, expr.span))
      end

      parse_compare(stop_types, stop_lexemes)
    end

    private def parse_compare(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      left = parse_add(stop_types, stop_lexemes)

      loop do
        skip_whitespace
        break if stop_at?(stop_types, stop_lexemes)

        if comparison_operator?
          op = current.lexeme
          advance
          right = parse_add(stop_types, stop_lexemes)
          left = AST::Binary.new(op, left, right, span_between(left.span, right.span))
          next
        end

        if keyword?("not") && peek_keyword?("in")
          advance
          skip_whitespace
          advance if keyword?("in")
          right = parse_add(stop_types, stop_lexemes)
          left = AST::Binary.new("not in", left, right, span_between(left.span, right.span))
          next
        end

        if keyword?("in")
          advance
          right = parse_add(stop_types, stop_lexemes)
          left = AST::Binary.new("in", left, right, span_between(left.span, right.span))
          next
        end

        if keyword?("is")
          left = parse_test(left, stop_types, stop_lexemes)
          next
        end

        break
      end

      left
    end

    private def parse_test(left : AST::Expr, stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      start_span = left.span
      advance
      skip_whitespace

      negated = false
      if keyword?("not")
        negated = true
        advance
        skip_whitespace
      end

      name = ""
      name_span = current.span
      if current.type == TokenType::Identifier
        name = current.lexeme
        name_span = current.span
        advance
      else
        emit_expected_token("Expected test name after 'is'.")
      end

      args = Array(AST::Expr).new
      kwargs = Array(AST::KeywordArg).new
      end_span = name_span

      skip_whitespace
      if punct?("(")
        args, kwargs, end_span = parse_call_args(stop_types, stop_lexemes)
      elsif starts_simple_expression?(stop_types, stop_lexemes)
        arg = parse_simple_expression(stop_types, stop_lexemes)
        args << arg
        end_span = arg.span
      end

      # test_name_span covers just the test name and args (for precise error reporting)
      test_name_span = span_between(name_span, end_span)
      AST::Test.new(left, name, args, kwargs, negated, span_between(start_span, end_span), test_name_span)
    end

    private def parse_add(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      left = parse_mul(stop_types, stop_lexemes)

      loop do
        skip_whitespace
        break if stop_at?(stop_types, stop_lexemes)
        break unless operator?("+", "-", "~")
        op = current.lexeme
        advance
        right = parse_mul(stop_types, stop_lexemes)
        left = AST::Binary.new(op, left, right, span_between(left.span, right.span))
      end

      left
    end

    private def parse_mul(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      left = parse_unary(stop_types, stop_lexemes)

      loop do
        skip_whitespace
        break if stop_at?(stop_types, stop_lexemes)
        break unless operator?("*", "/", "//", "%")
        op = current.lexeme
        advance
        right = parse_unary(stop_types, stop_lexemes)
        left = AST::Binary.new(op, left, right, span_between(left.span, right.span))
      end

      left
    end

    private def parse_power(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      left = parse_postfix(stop_types, stop_lexemes)

      loop do
        skip_whitespace
        break if stop_at?(stop_types, stop_lexemes)
        break unless operator?("**")
        op = current.lexeme
        advance
        right = parse_unary(stop_types, stop_lexemes)
        left = AST::Binary.new(op, left, right, span_between(left.span, right.span))
      end

      left
    end

    private def parse_unary(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      skip_whitespace
      if operator?("+", "-")
        op = current.lexeme
        start_span = current.span
        advance
        expr = parse_unary(stop_types, stop_lexemes)
        return AST::Unary.new(op, expr, span_between(start_span, expr.span))
      end

      parse_power(stop_types, stop_lexemes)
    end

    private def parse_postfix(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      left = parse_primary(stop_types, stop_lexemes)

      loop do
        skip_whitespace
        break if stop_at?(stop_types, stop_lexemes)

        if punct?(".")
          start_span = left.span
          advance
          if current.type == TokenType::Identifier || current.type == TokenType::Number
            name = current.lexeme
            end_span = current.span
            advance
            left = AST::GetAttr.new(left, name, span_between(start_span, end_span))
          else
            emit_expected_token("Expected attribute name or integer index after '.'.")
          end
          next
        end

        if punct?("[")
          start_span = left.span
          advance
          index = parse_expression([TokenType::Punct], ["]"])
          skip_whitespace
          end_span = index.span
          if punct?("]")
            end_span = current.span
            advance
          else
            emit_expected_token("Expected ']' to close index.")
          end
          left = AST::GetItem.new(left, index, span_between(start_span, end_span))
          next
        end

        if punct?("(")
          args, kwargs, end_span = parse_call_args(stop_types, stop_lexemes)
          left = AST::Call.new(left, args, kwargs, span_between(left.span, end_span))
          next
        end

        if operator?("|")
          start_span = left.span
          advance
          skip_whitespace
          name = ""
          name_span = current.span
          if current.type == TokenType::Identifier
            name = current.lexeme
            name_span = current.span
            advance
          else
            emit_expected_token("Expected filter name after '|'.")
          end

          args = Array(AST::Expr).new
          kwargs = Array(AST::KeywordArg).new
          end_span = name_span
          skip_whitespace
          if punct?("(")
            args, kwargs, end_span = parse_call_args(stop_types, stop_lexemes)
          elsif starts_simple_expression?(stop_types, stop_lexemes)
            arg = parse_simple_expression(stop_types, stop_lexemes)
            args << arg
            end_span = arg.span
          end

          # name_span covers just the filter name and args (for precise error reporting)
          filter_name_span = span_between(name_span, end_span)
          left = AST::Filter.new(left, name, args, kwargs, span_between(start_span, end_span), filter_name_span)
          next
        end

        break
      end

      left
    end

    private def starts_simple_expression?(stop_types : Array(TokenType), stop_lexemes : Array(String)) : Bool
      return false if stop_at?(stop_types, stop_lexemes)
      case current.type
      when TokenType::Identifier, TokenType::Number, TokenType::String
        true
      when TokenType::Punct
        punct?("(") || punct?("[") || punct?("{")
      else
        false
      end
    end

    private def parse_simple_expression(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      expr = parse_primary(stop_types, stop_lexemes)

      loop do
        skip_whitespace
        break if stop_at?(stop_types, stop_lexemes)
        break if operator?("|")

        if punct?(".")
          start_span = expr.span
          advance
          if current.type == TokenType::Identifier || current.type == TokenType::Number
            name = current.lexeme
            end_span = current.span
            advance
            expr = AST::GetAttr.new(expr, name, span_between(start_span, end_span))
          else
            emit_expected_token("Expected attribute name or integer index after '.'.")
          end
          next
        end

        if punct?("[")
          start_span = expr.span
          advance
          index = parse_expression([TokenType::Punct], ["]"])
          skip_whitespace
          end_span = index.span
          if punct?("]")
            end_span = current.span
            advance
          else
            emit_expected_token("Expected ']' to close index.")
          end
          expr = AST::GetItem.new(expr, index, span_between(start_span, end_span))
          next
        end

        if punct?("(")
          args, kwargs, end_span = parse_call_args(stop_types, stop_lexemes)
          expr = AST::Call.new(expr, args, kwargs, span_between(expr.span, end_span))
          next
        end

        break
      end

      expr
    end

    private def parse_primary(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      skip_whitespace
      if stop_at?(stop_types, stop_lexemes)
        emit_diagnostic(DiagnosticType::ExpectedExpression, "Expected expression.")
        return AST::Literal.new(nil, current.span)
      end

      case current.type
      when TokenType::Identifier
        lexeme = current.lexeme
        span = current.span
        advance
        case lexeme
        when "true"
          AST::Literal.new(true, span)
        when "false"
          AST::Literal.new(false, span)
        when "none", "null"
          AST::Literal.new(nil, span)
        else
          AST::Name.new(lexeme, span)
        end
      when TokenType::Number
        span = current.span
        value = number_value(current.lexeme)
        advance
        AST::Literal.new(value, span)
      when TokenType::String
        span = current.span
        value = unquote(current.lexeme)
        advance
        AST::Literal.new(value, span)
      when TokenType::Punct
        if punct?("(")
          parse_group_or_tuple
        elsif punct?("[")
          parse_list_literal
        elsif punct?("{")
          parse_dict_literal
        else
          emit_unexpected_token("expression")
          advance
          recover_expression_start(stop_types, stop_lexemes)
          return AST::Literal.new(nil, current.span) if stop_at?(stop_types, stop_lexemes)
          return parse_primary(stop_types, stop_lexemes) if expression_start?
          AST::Literal.new(nil, current.span)
        end
      else
        emit_unexpected_token("expression")
        advance
        recover_expression_start(stop_types, stop_lexemes)
        return AST::Literal.new(nil, current.span) if stop_at?(stop_types, stop_lexemes)
        return parse_primary(stop_types, stop_lexemes) if expression_start?
        AST::Literal.new(nil, current.span)
      end
    end

    private def parse_group_or_tuple : AST::Expr
      start_span = current.span
      advance
      skip_whitespace

      if punct?(")")
        end_span = current.span
        advance
        return AST::Group.new(AST::Literal.new(nil, end_span), span_between(start_span, end_span))
      end

      first = parse_expression([TokenType::Punct], [",", ")"])
      skip_whitespace

      if punct?(",")
        items = Array(AST::Expr).new
        items << first
        while punct?(",")
          advance
          skip_whitespace
          break if punct?(")")
          items << parse_expression([TokenType::Punct], [",", ")"])
          skip_whitespace
        end

        end_span = items.last.span
        if punct?(")")
          end_span = current.span
          advance
        else
          emit_expected_token("Expected ')' to close tuple.")
        end

        return AST::TupleLiteral.new(items, span_between(start_span, end_span))
      end

      if punct?(")")
        end_span = current.span
        advance
        AST::Group.new(first, span_between(start_span, end_span))
      else
        emit_expected_token("Expected ')' to close group.")
        AST::Group.new(first, span_between(start_span, first.span))
      end
    end

    private def parse_list_literal : AST::Expr
      start_span = current.span
      advance
      items = Array(AST::Expr).new
      skip_whitespace

      if punct?("]")
        end_span = current.span
        advance
        return AST::ListLiteral.new(items, span_between(start_span, end_span))
      end

      loop do
        item = parse_expression([TokenType::Punct], [",", "]"])
        items << item
        skip_whitespace
        break unless punct?(",")
        advance
        skip_whitespace
        break if punct?("]")
      end

      end_span = items.last.span
      if punct?("]")
        end_span = current.span
        advance
      else
        emit_expected_token("Expected ']' to close list.")
      end

      AST::ListLiteral.new(items, span_between(start_span, end_span))
    end

    private def parse_dict_literal : AST::Expr
      start_span = current.span
      advance
      pairs = Array(AST::DictEntry).new
      skip_whitespace

      if punct?("}")
        end_span = current.span
        advance
        return AST::DictLiteral.new(pairs, span_between(start_span, end_span))
      end

      loop do
        key = parse_expression([TokenType::Punct], [":", "}", ","])
        skip_whitespace
        if punct?(":")
          advance
        else
          emit_expected_token("Expected ':' in dict literal.")
        end
        skip_whitespace
        value = parse_expression([TokenType::Punct], [",", "}"])
        pairs << AST::DictEntry.new(key, value, span_between(key.span, value.span))
        skip_whitespace
        break unless punct?(",")
        advance
        skip_whitespace
        break if punct?("}")
      end

      end_span = pairs.last.span
      if punct?("}")
        end_span = current.span
        advance
      else
        emit_expected_token("Expected '}' to close dict.")
      end

      AST::DictLiteral.new(pairs, span_between(start_span, end_span))
    end

    private def parse_call_args(stop_types : Array(TokenType), stop_lexemes : Array(String)) : {Array(AST::Expr), Array(AST::KeywordArg), Span}
      start_span = current.span
      advance
      args = Array(AST::Expr).new
      kwargs = Array(AST::KeywordArg).new
      skip_whitespace

      if punct?(")")
        end_span = current.span
        advance
        return {args, kwargs, span_between(start_span, end_span)}
      end

      loop do
        skip_whitespace
        if keyword_arg_start?
          name = current.lexeme
          name_span = current.span
          advance
          skip_whitespace
          if operator?("=")
            advance
          else
            emit_expected_token("Expected '=' for keyword argument.")
          end
          skip_whitespace
          value = parse_expression([TokenType::Punct], [",", ")"])
          kwargs << AST::KeywordArg.new(name, value, span_between(name_span, value.span))
        else
          args << parse_expression([TokenType::Punct], [",", ")"])
        end

        skip_whitespace
        break unless punct?(",")
        advance
        skip_whitespace
        break if punct?(")")
      end

      end_span = previous.span
      if punct?(")")
        end_span = current.span
        advance
      else
        emit_expected_token("Expected ')' to close arguments.")
      end

      {args, kwargs, span_between(start_span, end_span)}
    end

    private def number_value(lexeme : String) : (Int64 | Float64)
      if lexeme.includes?(".")
        lexeme.to_f64
      else
        lexeme.to_i64
      end
    end

    private def unquote(lexeme : String) : String
      return "" if lexeme.size < 2
      lexeme[1, lexeme.size - 2]
    end

    private def stop_at?(stop_types : Array(TokenType), stop_lexemes : Array(String)) : Bool
      return false unless stop_types.includes?(current.type)
      return true if stop_lexemes.empty?
      stop_lexemes.includes?(current.lexeme)
    end

    private def keyword?(value : String) : Bool
      current.type == TokenType::Identifier && current.lexeme == value
    end

    private def peek_keyword?(value : String) : Bool
      token = peek_non_whitespace
      return false unless token
      token.type == TokenType::Identifier && token.lexeme == value
    end

    private def operator?(*ops : String) : Bool
      return false unless current.type == TokenType::Operator
      ops.any? { |op| op == current.lexeme }
    end

    private def punct?(value : String) : Bool
      current.type == TokenType::Punct && current.lexeme == value
    end

    private def comparison_operator? : Bool
      return false unless current.type == TokenType::Operator
      case current.lexeme
      when "==", "!=", "<", "<=", ">", ">="
        true
      else
        false
      end
    end

    private def keyword_arg_start? : Bool
      return false unless current.type == TokenType::Identifier
      token = peek_non_whitespace
      return false unless token
      token.type == TokenType::Operator && token.lexeme == "="
    end

    private def peek_non_whitespace : Token?
      i = @index + 1
      while i < @tokens.size
        token = @tokens[i]
        return token unless token.type == TokenType::Whitespace
        i += 1
      end
      nil
    end

    private def template_span(nodes : Array(AST::Node)) : Span
      if nodes.empty?
        Span.new(current.span.start_pos, current.span.start_pos)
      else
        span_between(nodes.first.span, nodes.last.span)
      end
    end

    def span_between(start_span : Span, end_span : Span) : Span
      Span.new(start_span.start_pos, end_span.end_pos)
    end

    private def trim_left_from_start(token : Token) : Bool
      token.lexeme.ends_with?("-")
    end

    private def trim_right_from_end(token : Token) : Bool
      token.lexeme.starts_with?("-")
    end

    private def peek_block_tag : String?
      i = @index + 1
      while i < @tokens.size
        token = @tokens[i]
        if token.type == TokenType::BlockEnd
          return
        end
        return token.lexeme if token.type == TokenType::Identifier
        i += 1
      end
      nil
    end

    private def has_end_tag_ahead?(end_tag : String) : Bool
      i = @index + 1
      while i < @tokens.size
        token = @tokens[i]
        if token.type == TokenType::BlockStart
          j = i + 1
          while j < @tokens.size && @tokens[j].type == TokenType::Whitespace
            j += 1
          end
          if j < @tokens.size && @tokens[j].type == TokenType::Identifier && @tokens[j].lexeme == end_tag
            return true
          end
        end
        i += 1
      end
      false
    end

    def skip_whitespace : Nil
      while current.type == TokenType::Whitespace
        advance
      end
    end

    def recover_to(stop_types : Array(TokenType)) : Nil
      while !at_end? && !stop_types.includes?(current.type)
        advance
      end
    end

    private def recover_expression_start(stop_types : Array(TokenType), stop_lexemes : Array(String)) : Nil
      while !at_end? && !stop_at?(stop_types, stop_lexemes) && !expression_start?
        advance
      end
    end

    private def expression_start? : Bool
      case current.type
      when TokenType::Identifier, TokenType::Number, TokenType::String
        true
      when TokenType::Punct
        case current.lexeme
        when "(", "[", "{"
          true
        else
          false
        end
      else
        false
      end
    end

    private def emit_unexpected_token(context : String) : Nil
      emit_diagnostic(DiagnosticType::UnexpectedToken, "Unexpected token in #{context}.")
    end

    private def emit_expected_token(message : String) : Nil
      emit_diagnostic(DiagnosticType::ExpectedToken, message)
    end

    private def emit_diagnostic(type : DiagnosticType, message : String) : Nil
      @diagnostics << Diagnostic.new(type, Severity::Error, message, current.span)
    end

    def current : Token
      @tokens[@index]
    end

    private def previous : Token
      @tokens[@index - 1]
    end

    def advance : Token
      @index += 1 if @index < @tokens.size - 1
      previous
    end

    private def at_end? : Bool
      current.type == TokenType::EOF
    end
  end
end
