pub type Token {
  Word(String)
  QuotedIdent(String)
  Number(String)
  StringLit(String)
  LParen
  RParen
  Comma
  Semicolon
  Dot
  LBracket
  RBracket
  Symbol(String)
}

pub type Positioned {
  Positioned(token: Token, start: Int, end: Int)
}

pub fn to_string(token: Token) -> String {
  case token {
    Word(w) -> w
    QuotedIdent(w) -> "\"" <> w <> "\""
    Number(n) -> n
    StringLit(s) -> "'" <> s <> "'"
    LParen -> "("
    RParen -> ")"
    Comma -> ","
    Semicolon -> ";"
    Dot -> "."
    LBracket -> "["
    RBracket -> "]"
    Symbol(s) -> s
  }
}
