import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Error {
  LexError(message: String, pos: Int)
  ParseError(message: String, pos: Int, hint: Option(String))
  UnknownStatement(word: String, pos: Int, hint: Option(String))
  UnknownType(name: String, pos: Int, hint: Option(String))
  UnmappedType(name: String, pos: Int)
  ValidationError(message: String, pos: Int, hint: Option(String))
  ConfigError(message: String, hint: Option(String))
  IoError(message: String)
}

pub fn render(err: Error, filename: String, source: String) -> String {
  let #(title, message, position, hint) = parts(err)
  case position {
    None -> header(title, message) <> render_hint(hint)
    Some(pos) -> {
      let #(line, col) = line_col(source, pos)
      let text = nth_line(source, line)
      let gutter = int.to_string(line)
      let pad = string.repeat(" ", string.length(gutter))
      header(title, "")
      <> pad
      <> "┌─ "
      <> filename
      <> ":"
      <> int.to_string(line)
      <> ":"
      <> int.to_string(col)
      <> "\n"
      <> pad
      <> " │\n"
      <> gutter
      <> " │ "
      <> text
      <> "\n"
      <> pad
      <> " │ "
      <> string.repeat(" ", col - 1)
      <> "^ "
      <> message
      <> "\n"
      <> render_hint(hint)
    }
  }
}

fn header(title: String, message: String) -> String {
  case message {
    "" -> "error: " <> title <> "\n"
    _ -> "error: " <> title <> "\n" <> message <> "\n"
  }
}

fn render_hint(hint: Option(String)) -> String {
  case hint {
    None -> ""
    Some(h) -> "\nHint: did you mean `" <> h <> "`?\n"
  }
}

fn parts(err: Error) -> #(String, String, Option(Int), Option(String)) {
  case err {
    LexError(m, pos) -> #("Syntax error", m, Some(pos), None)
    ParseError(m, pos, hint) -> #("Syntax error", m, Some(pos), hint)
    UnknownStatement(w, pos, hint) -> #(
      "Unknown statement",
      "I don't know the statement `" <> w <> "`",
      Some(pos),
      hint,
    )
    UnknownType(n, pos, hint) -> #(
      "Unknown type",
      "I have no Gleam mapping for the SQL type `" <> n <> "`",
      Some(pos),
      hint,
    )
    UnmappedType(n, pos) -> #(
      "Unsupported type",
      "`"
        <> n
        <> "` is a Postgres type that pog has no decoder for, so there is no "
        <> "built-in mapping for it. Add one to glsql.toml, using a Gleam type "
        <> "that matches what the driver returns for this column:\n\n    [types."
        <> n
        <> "]\n    gleam_type = \"String\"\n    decoder = \"decode.string\"\n"
        <> "    encoder = \"pog.text($)\"",
      Some(pos),
      None,
    )
    ValidationError(m, pos, hint) -> #("Invalid schema", m, Some(pos), hint)
    ConfigError(m, hint) -> #("Invalid configuration", m, None, hint)
    IoError(m) -> #("File error", m, None, None)
  }
}

fn line_col(source: String, pos: Int) -> #(Int, Int) {
  let before = string.slice(source, 0, pos)
  let lines = string.split(before, "\n")
  let line = list.length(lines)
  let col = case list.last(lines) {
    Ok(l) -> string.length(l) + 1
    Error(Nil) -> 1
  }
  #(line, col)
}

fn nth_line(source: String, line: Int) -> String {
  case
    source
    |> string.split("\n")
    |> list.drop(line - 1)
    |> list.first
  {
    Ok(l) -> l
    Error(Nil) -> ""
  }
}
