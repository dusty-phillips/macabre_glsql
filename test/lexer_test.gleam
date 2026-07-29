import glsql/internal/lexer
import glsql/internal/token.{
  type Positioned, Comma, LParen, Number, Positioned, QuotedIdent, RParen,
  Semicolon, StringLit, Word,
}

pub fn lex_basic_test() {
  let assert Ok(tokens) = lexer.lex("create table users (id uuid);")
  let bare = tokens |> echo_tokens
  assert bare
    == [
      Word("create"),
      Word("table"),
      Word("users"),
      LParen,
      Word("id"),
      Word("uuid"),
      RParen,
      Semicolon,
    ]
}

fn echo_tokens(tokens: List(Positioned)) -> List(token.Token) {
  case tokens {
    [] -> []
    [Positioned(t, _, _), ..rest] -> [t, ..echo_tokens(rest)]
  }
}

pub fn lex_preserves_case_test() {
  let assert Ok([Positioned(t, _, _), ..]) = lexer.lex("CREATE")
  assert t == Word("CREATE")
}

pub fn lex_whitespace_kinds_test() {
  let assert Ok(tokens) = lexer.lex("  create\n\ttable\r\nusers ")
  assert echo_tokens(tokens) == [Word("create"), Word("table"), Word("users")]
}

pub fn lex_positions_test() {
  let assert Ok([_, Positioned(_, start, end), ..]) = lexer.lex("create table")
  assert start == 7
  assert end == 12
}

pub fn lex_quoted_ident_test() {
  let assert Ok([Positioned(t, _, _), ..]) = lexer.lex("\"user table\"")
  assert t == QuotedIdent("user table")
}

pub fn lex_line_comment_test() {
  let assert Ok(tokens) = lexer.lex("create -- a comment\ntable")
  assert echo_tokens(tokens) == [Word("create"), Word("table")]
}

pub fn lex_block_comment_test() {
  let assert Ok(tokens) = lexer.lex("create /* a\ncomment */ table")
  assert echo_tokens(tokens) == [Word("create"), Word("table")]
}

pub fn lex_number_and_comma_test() {
  let assert Ok(tokens) = lexer.lex("numeric(10,2)")
  assert echo_tokens(tokens)
    == [Word("numeric"), LParen, Number("10"), Comma, Number("2"), RParen]
}

pub fn lex_unterminated_quote_test() {
  let assert Error(_) = lexer.lex("\"unterminated")
}

pub fn lex_unterminated_block_comment_test() {
  let assert Error(_) = lexer.lex("create /* forever")
}

pub fn lex_dollar_quoted_string_test() {
  let assert Ok([Positioned(t, _, _)]) = lexer.lex("$$abc$$")
  assert t == StringLit("abc")
}

pub fn lex_dollar_quoted_with_tag_test() {
  let assert Ok([Positioned(t, _, _)]) = lexer.lex("$tag$it's fine$tag$")
  assert t == StringLit("it's fine")
}

pub fn lex_dollar_quoted_ignores_mismatched_tag_test() {
  let assert Ok(tokens) = lexer.lex("$a$inner$b$still$a$")
  assert echo_tokens(tokens) == [StringLit("inner$b$still")]
}

pub fn lex_unterminated_dollar_quote_test() {
  let assert Error(_) = lexer.lex("$$abc")
}
