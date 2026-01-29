module Jinja
  class Parser
    getter diagnostics : Array(Diagnostic)

    def initialize(tokens : Array(Token)) : Nil
      @tokens = tokens
      @index = 0
      @diagnostics = Array(Diagnostic).new
    end

    def parse : AST::Template
      nodes = Array(AST::Node).new

      while !at_end?
        case current.type
        when TokenType::Text
          nodes << AST::Text.new(current.lexeme, current.span)
          advance
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
      start_span = current.span
      advance
      skip_whitespace

      expr = parse_expression([TokenType::VarEnd])
      skip_whitespace

      end_span = if current.type == TokenType::VarEnd
                   token = advance
                   token.span
                 else
                   emit_expected_token("Expected '}}' to close expression.")
                   recover_to([TokenType::VarEnd])
                   if current.type == TokenType::VarEnd
                     token = advance
                     token.span
                   else
                     previous.span
                   end
                 end

      AST::Output.new(expr, span_between(start_span, end_span))
    end

    private def parse_block : AST::Node?
      start_span = current.span
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

      case tag
      when "if"
        parse_if(start_span)
      when "for"
        parse_for(start_span)
      when "endif", "endfor"
        emit_diagnostic(DiagnosticType::UnexpectedEndTag, "Unexpected '#{tag}'.")
        recover_to([TokenType::BlockEnd])
        advance if current.type == TokenType::BlockEnd
        nil
      else
        emit_diagnostic(DiagnosticType::UnknownTag, "Unknown tag '#{tag}'.")
        recover_to([TokenType::BlockEnd])
        advance if current.type == TokenType::BlockEnd
        nil
      end
    end

    private def parse_if(start_span : Span) : AST::If
      skip_whitespace
      test = parse_expression([TokenType::BlockEnd])
      skip_whitespace

      if current.type == TokenType::BlockEnd
        advance
      else
        emit_expected_token("Expected '%}' to close if tag.")
        recover_to([TokenType::BlockEnd])
        advance if current.type == TokenType::BlockEnd
      end

      body, end_span = parse_until_end_tag("endif")
      end_span ||= start_span
      AST::If.new(test, body, Array(AST::Node).new, span_between(start_span, end_span))
    end

    private def parse_for(start_span : Span) : AST::For
      skip_whitespace

      target = if current.type == TokenType::Identifier
                 name = AST::Name.new(current.lexeme, current.span)
                 advance
                 name
               else
                 emit_expected_token("Expected loop variable name after 'for'.")
                 AST::Name.new("", current.span)
               end

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
        advance
      else
        emit_expected_token("Expected '%}' to close for tag.")
        recover_to([TokenType::BlockEnd])
        advance if current.type == TokenType::BlockEnd
      end

      body, end_span = parse_until_end_tag("endfor")
      end_span ||= start_span
      AST::For.new(target, iter, body, Array(AST::Node).new, span_between(start_span, end_span))
    end

    private def parse_until_end_tag(end_tag : String) : {Array(AST::Node), Span?}
      nodes = Array(AST::Node).new

      while !at_end?
        if current.type == TokenType::BlockStart
          tag = peek_block_tag
          if tag == end_tag
            end_span = consume_end_tag
            return {nodes, end_span}
          end

          node = parse_block
          nodes << node if node
          next
        end

        case current.type
        when TokenType::Text
          nodes << AST::Text.new(current.lexeme, current.span)
          advance
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

    private def consume_end_tag : Span
      start_span = current.span
      advance
      skip_whitespace
      if current.type == TokenType::Identifier
        advance
      else
        emit_expected_token("Expected end tag name.")
      end
      skip_whitespace
      if current.type == TokenType::BlockEnd
        end_span = current.span
        advance
        span_between(start_span, end_span)
      else
        emit_expected_token("Expected '%}' to close end tag.")
        start_span
      end
    end

    private def parse_expression(stop_types : Array(TokenType), stop_lexemes : Array(String) = Array(String).new) : AST::Expr
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
          advance
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
      end

      AST::Test.new(left, name, args, kwargs, negated, span_between(start_span, end_span))
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
      left = parse_power(stop_types, stop_lexemes)

      loop do
        skip_whitespace
        break if stop_at?(stop_types, stop_lexemes)
        break unless operator?("*", "/", "//", "%")
        op = current.lexeme
        advance
        right = parse_power(stop_types, stop_lexemes)
        left = AST::Binary.new(op, left, right, span_between(left.span, right.span))
      end

      left
    end

    private def parse_power(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      left = parse_unary(stop_types, stop_lexemes)
      skip_whitespace

      if operator?("**")
        op = current.lexeme
        advance
        right = parse_power(stop_types, stop_lexemes)
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

      parse_postfix(stop_types, stop_lexemes)
    end

    private def parse_postfix(stop_types : Array(TokenType), stop_lexemes : Array(String)) : AST::Expr
      left = parse_primary(stop_types, stop_lexemes)

      loop do
        skip_whitespace
        break if stop_at?(stop_types, stop_lexemes)

        if punct?(".")
          start_span = left.span
          advance
          if current.type == TokenType::Identifier
            name = current.lexeme
            end_span = current.span
            advance
            left = AST::GetAttr.new(left, name, span_between(start_span, end_span))
          else
            emit_expected_token("Expected attribute name after '.'.")
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
          end

          left = AST::Filter.new(left, name, args, kwargs, span_between(start_span, end_span))
          next
        end

        break
      end

      left
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
          AST::Literal.new(nil, current.span)
        end
      else
        emit_unexpected_token("expression")
        advance
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

    private def span_between(start_span : Span, end_span : Span) : Span
      Span.new(start_span.start_pos, end_span.end_pos)
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

    private def skip_whitespace : Nil
      while current.type == TokenType::Whitespace
        advance
      end
    end

    private def recover_to(stop_types : Array(TokenType)) : Nil
      while !at_end? && !stop_types.includes?(current.type)
        advance
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

    private def current : Token
      @tokens[@index]
    end

    private def previous : Token
      @tokens[@index - 1]
    end

    private def advance : Token
      @index += 1 if @index < @tokens.size - 1
      previous
    end

    private def at_end? : Bool
      current.type == TokenType::EOF
    end
  end
end
