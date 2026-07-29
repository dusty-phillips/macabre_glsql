import gleam/list
import gleam/order
import gleam/result
import gleam/string
import glsql/internal/error.{type Error, LexError}
import glsql/internal/token.{type Positioned, type Token, Positioned}

pub fn lex(src: String) -> Result(List(Positioned), Error) {
  do_lex(string.to_graphemes(src), 0, [])
  |> result.map(list.reverse)
}

fn do_lex(
  chars: List(String),
  pos: Int,
  acc: List(Positioned),
) -> Result(List(Positioned), Error) {
  case chars {
    [] -> Ok(acc)

    [" ", ..rest] | ["\n", ..rest] | ["\t", ..rest] | ["\r", ..rest] ->
      do_lex(rest, pos + 1, acc)

    ["\r\n", ..rest] -> do_lex(rest, pos + 1, acc)

    ["-", "-", ..rest] -> {
      let #(_, rest, pos) = take_until_newline(rest, pos + 2)
      do_lex(rest, pos, acc)
    }

    ["/", "*", ..rest] ->
      case skip_block_comment(rest, pos + 2) {
        Ok(#(rest, pos)) -> do_lex(rest, pos, acc)
        Error(e) -> Error(e)
      }

    ["(", ..rest] -> punct(token.LParen, rest, pos, acc)
    [")", ..rest] -> punct(token.RParen, rest, pos, acc)
    [",", ..rest] -> punct(token.Comma, rest, pos, acc)
    [";", ..rest] -> punct(token.Semicolon, rest, pos, acc)
    [".", ..rest] -> punct(token.Dot, rest, pos, acc)
    ["[", ..rest] -> punct(token.LBracket, rest, pos, acc)
    ["]", ..rest] -> punct(token.RBracket, rest, pos, acc)

    ["\"", ..rest] ->
      case take_delimited(rest, "\"", pos + 1, "") {
        Ok(#(text, rest, end)) ->
          do_lex(rest, end, [
            Positioned(token.QuotedIdent(text), pos, end),
            ..acc
          ])
        Error(Nil) -> Error(LexError("Unterminated quoted identifier", pos))
      }

    ["'", ..rest] ->
      case take_delimited(rest, "'", pos + 1, "") {
        Ok(#(text, rest, end)) ->
          do_lex(rest, end, [Positioned(token.StringLit(text), pos, end), ..acc])
        Error(Nil) -> Error(LexError("Unterminated string literal", pos))
      }

    ["$", ..] ->
      case try_dollar_quote_open(chars, pos) {
        Error(Nil) -> {
          let #(text, rest, end) = take_while(chars, is_word_char, pos, "")
          do_lex(rest, end, [Positioned(token.Word(text), pos, end), ..acc])
        }
        Ok(#(tag, body, body_pos)) ->
          case scan_dollar_quote_body(body, tag, body_pos, "") {
            Ok(#(text, rest, end)) ->
              do_lex(rest, end, [
                Positioned(token.StringLit(text), pos, end),
                ..acc
              ])
            Error(Nil) ->
              Error(LexError("Unterminated dollar-quoted string", pos))
          }
      }

    [c, ..rest] ->
      case is_digit(c) {
        True -> {
          let #(text, rest, end) = take_while(chars, is_number_char, pos, "")
          do_lex(rest, end, [Positioned(token.Number(text), pos, end), ..acc])
        }
        False ->
          case is_word_char(c) {
            True -> {
              let #(text, rest, end) = take_while(chars, is_word_char, pos, "")
              do_lex(rest, end, [Positioned(token.Word(text), pos, end), ..acc])
            }
            False ->
              do_lex(rest, pos + 1, [
                Positioned(token.Symbol(c), pos, pos + 1),
                ..acc
              ])
          }
      }
  }
}

fn punct(
  tok: Token,
  rest: List(String),
  pos: Int,
  acc: List(Positioned),
) -> Result(List(Positioned), Error) {
  do_lex(rest, pos + 1, [Positioned(tok, pos, pos + 1), ..acc])
}

fn in_range(c: String, low: String, high: String) -> Bool {
  string.compare(c, low) != order.Lt && string.compare(c, high) != order.Gt
}

fn is_digit(c: String) -> Bool {
  in_range(c, "0", "9")
}

fn is_number_char(c: String) -> Bool {
  is_digit(c) || c == "."
}

fn is_word_char(c: String) -> Bool {
  is_digit(c)
  || in_range(c, "a", "z")
  || in_range(c, "A", "Z")
  || c == "_"
  || c == "$"
}

fn take_while(
  chars: List(String),
  pred: fn(String) -> Bool,
  pos: Int,
  acc: String,
) -> #(String, List(String), Int) {
  case chars {
    [c, ..rest] ->
      case pred(c) {
        True -> take_while(rest, pred, pos + 1, acc <> c)
        False -> #(acc, chars, pos)
      }
    [] -> #(acc, [], pos)
  }
}

fn take_until_newline(
  chars: List(String),
  pos: Int,
) -> #(Nil, List(String), Int) {
  case chars {
    [] -> #(Nil, [], pos)
    ["\n", ..rest] -> #(Nil, rest, pos + 1)
    [_, ..rest] -> take_until_newline(rest, pos + 1)
  }
}

fn skip_block_comment(
  chars: List(String),
  pos: Int,
) -> Result(#(List(String), Int), Error) {
  case chars {
    [] -> Error(LexError("Unterminated block comment", pos))
    ["*", "/", ..rest] -> Ok(#(rest, pos + 2))
    [_, ..rest] -> skip_block_comment(rest, pos + 1)
  }
}

fn is_tag_char(c: String) -> Bool {
  is_digit(c) || in_range(c, "a", "z") || in_range(c, "A", "Z") || c == "_"
}

fn try_dollar_quote_open(
  chars: List(String),
  pos: Int,
) -> Result(#(String, List(String), Int), Nil) {
  case chars {
    ["$", ..rest] -> {
      let #(tag, rest, tag_end) = take_while(rest, is_tag_char, pos + 1, "")
      case rest {
        ["$", ..rest] -> Ok(#(tag, rest, tag_end + 1))
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

fn scan_dollar_quote_body(
  chars: List(String),
  tag: String,
  pos: Int,
  acc: String,
) -> Result(#(String, List(String), Int), Nil) {
  let closer = string.to_graphemes("$" <> tag <> "$")
  case chars {
    [] -> Error(Nil)
    _ ->
      case starts_with_seq(chars, closer) {
        True -> {
          let closer_len = list.length(closer)
          Ok(#(acc, list.drop(chars, closer_len), pos + closer_len))
        }
        False -> {
          let assert [c, ..rest] = chars
          scan_dollar_quote_body(rest, tag, pos + 1, acc <> c)
        }
      }
  }
}

fn starts_with_seq(chars: List(String), seq: List(String)) -> Bool {
  case seq {
    [] -> True
    [s, ..srest] ->
      case chars {
        [c, ..crest] -> c == s && starts_with_seq(crest, srest)
        [] -> False
      }
  }
}

fn take_delimited(
  chars: List(String),
  delim: String,
  pos: Int,
  acc: String,
) -> Result(#(String, List(String), Int), Nil) {
  case chars {
    [] -> Error(Nil)
    [c, ..rest] ->
      case c == delim {
        True -> Ok(#(acc, rest, pos + 1))
        False -> take_delimited(rest, delim, pos + 1, acc <> c)
      }
  }
}
