module Jinja
  class Parser
    getter diagnostics : Array(Diagnostic)

    def initialize(tokens : Array(Token)) : Nil
      @tokens = tokens
      @index = 0
      @diagnostics = [] of Diagnostic
    end

    def parse : AST::Template
      nodes = [] of AST::Node

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
      AST::If.new(test, body, [] of AST::Node, span_between(start_span, end_span))
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
      AST::For.new(target, iter, body, [] of AST::Node, span_between(start_span, end_span))
    end

    private def parse_until_end_tag(end_tag : String) : {Array(AST::Node), Span?}
      nodes = [] of AST::Node

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

    private def parse_expression(stop_types : Array(TokenType)) : AST::Expr
      skip_whitespace
      if stop_types.includes?(current.type)
        emit_diagnostic(DiagnosticType::ExpectedExpression, "Expected expression.")
        return AST::Literal.new(nil, current.span)
      end

      parse_precedence(0, stop_types)
    end

    private def parse_precedence(min_prec : Int32, stop_types : Array(TokenType)) : AST::Expr
      left = parse_primary(stop_types)

      loop do
        skip_whitespace
        break if stop_types.includes?(current.type)
        break unless current.type == TokenType::Operator

        op = current.lexeme
        prec = precedence_for(op)
        break unless prec
        break if prec < min_prec

        advance
        right = parse_precedence(prec + 1, stop_types)
        left = AST::Binary.new(op, left, right, span_between(left.span, right.span))
      end

      left
    end

    private def parse_primary(stop_types : Array(TokenType)) : AST::Expr
      skip_whitespace
      if stop_types.includes?(current.type)
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
        if current.lexeme == "("
          start_span = current.span
          advance
          expr = parse_expression([TokenType::Punct])
          if current.type == TokenType::Punct && current.lexeme == ")"
            end_span = current.span
            advance
            AST::Group.new(expr, span_between(start_span, end_span))
          else
            emit_expected_token("Expected ')' to close group.")
            AST::Group.new(expr, span_between(start_span, expr.span))
          end
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

    private def precedence_for(op : String) : Int32?
      case op
      when "==", "!="
        1
      when "+", "-"
        2
      when "*", "/"
        3
      end
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
