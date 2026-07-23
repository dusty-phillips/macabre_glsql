import gleam/option.{type Option}

pub type Error {
  LexError(message: String, pos: Int)
  ParseError(message: String, pos: Int, hint: Option(String))
  UnknownStatement(word: String, pos: Int, hint: Option(String))
  UnknownType(name: String, pos: Int, hint: Option(String))
  ValidationError(message: String, pos: Int, hint: Option(String))
  ConfigError(message: String, hint: Option(String))
  IoError(message: String)
}
