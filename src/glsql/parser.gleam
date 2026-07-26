import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import glsql/ast
import glsql/error.{type Error, ParseError}
import glsql/token.{type Positioned, Positioned}

type Tokens =
  List(Positioned)

pub fn parse(tokens: Tokens) -> Result(ast.SchemaAst, Error) {
  use tables <- result.try(parse_statements(tokens, []))
  Ok(ast.SchemaAst(tables: list.reverse(tables)))
}

fn parse_statements(
  tokens: Tokens,
  acc: List(ast.Table),
) -> Result(List(ast.Table), Error) {
  case tokens {
    [] -> Ok(acc)
    [Positioned(token.Semicolon, _, _), ..rest] -> parse_statements(rest, acc)
    _ -> {
      use #(table, rest) <- result.try(parse_create_table(tokens))
      parse_statements(rest, [table, ..acc])
    }
  }
}

fn parse_create_table(tokens: Tokens) -> Result(#(ast.Table, Tokens), Error) {
  use #(pos, rest) <- result.try(keyword(tokens, "create"))
  use #(_, rest) <- result.try(keyword(rest, "table"))
  let rest = skip_if_not_exists(rest)
  use #(schema, name, rest) <- result.try(qualified_name(rest))
  use #(_, rest) <- result.try(expect(rest, token.LParen, "("))
  use #(columns, rest) <- result.try(parse_column_list(rest, []))
  use #(_, rest) <- result.try(expect(rest, token.RParen, ")"))
  Ok(#(
    ast.Table(
      name: name,
      schema: schema,
      columns: list.reverse(columns),
      constraints: [],
      pos: pos,
    ),
    rest,
  ))
}

fn parse_column_list(
  tokens: Tokens,
  acc: List(ast.Column),
) -> Result(#(List(ast.Column), Tokens), Error) {
  use #(column, rest) <- result.try(parse_column(tokens))
  case rest {
    [Positioned(token.Comma, _, _), ..rest] ->
      parse_column_list(rest, [column, ..acc])
    _ -> Ok(#([column, ..acc], rest))
  }
}

fn parse_column(tokens: Tokens) -> Result(#(ast.Column, Tokens), Error) {
  use #(name, pos, rest) <- result.try(identifier(tokens))
  use #(sql_type, rest) <- result.try(parse_type(rest))
  Ok(#(
    ast.Column(name: name, sql_type: sql_type, constraints: [], pos: pos),
    rest,
  ))
}

fn parse_type(tokens: Tokens) -> Result(#(ast.SqlType, Tokens), Error) {
  use #(name, pos, rest) <- result.try(identifier(tokens))
  use #(args, rest) <- result.try(parse_type_args(rest))
  let #(dims, rest) = parse_array_dims(rest, 0)
  Ok(#(ast.SqlType(name: name, args: args, array_dims: dims, pos: pos), rest))
}

fn parse_type_args(tokens: Tokens) -> Result(#(List(String), Tokens), Error) {
  case tokens {
    [Positioned(token.LParen, _, _), ..rest] -> collect_args(rest, [])
    _ -> Ok(#([], tokens))
  }
}

fn collect_args(
  tokens: Tokens,
  acc: List(String),
) -> Result(#(List(String), Tokens), Error) {
  case tokens {
    [Positioned(token.Number(n), _, _), Positioned(token.Comma, _, _), ..rest] ->
      collect_args(rest, [n, ..acc])
    [Positioned(token.Number(n), _, _), Positioned(token.RParen, _, _), ..rest] ->
      Ok(#(list.reverse([n, ..acc]), rest))
    [Positioned(token.Word(w), _, _), Positioned(token.RParen, _, _), ..rest] ->
      Ok(#(list.reverse([w, ..acc]), rest))
    [Positioned(_, pos, _), ..] ->
      Error(ParseError("Expected a type argument", pos, None))
    [] -> Error(ParseError("Unexpected end of file in type arguments", 0, None))
  }
}

fn parse_array_dims(tokens: Tokens, count: Int) -> #(Int, Tokens) {
  case tokens {
    [
      Positioned(token.LBracket, _, _),
      Positioned(token.RBracket, _, _),
      ..rest
    ] -> parse_array_dims(rest, count + 1)
    _ -> #(count, tokens)
  }
}

fn skip_if_not_exists(tokens: Tokens) -> Tokens {
  case tokens {
    [
      Positioned(token.Word(a), _, _),
      Positioned(token.Word(b), _, _),
      Positioned(token.Word(c), _, _),
      ..rest
    ] ->
      case
        string.lowercase(a),
        string.lowercase(b),
        string.lowercase(c)
      {
        "if", "not", "exists" -> rest
        _, _, _ -> tokens
      }
    _ -> tokens
  }
}

fn qualified_name(
  tokens: Tokens,
) -> Result(#(Option(String), String, Tokens), Error) {
  use #(first, _pos, rest) <- result.try(identifier(tokens))
  case rest {
    [Positioned(token.Dot, _, _), ..rest] -> {
      use #(second, _, rest) <- result.try(identifier(rest))
      Ok(#(Some(first), second, rest))
    }
    _ -> Ok(#(None, first, rest))
  }
}

fn identifier(tokens: Tokens) -> Result(#(String, Int, Tokens), Error) {
  case tokens {
    [Positioned(token.Word(w), pos, _), ..rest] -> Ok(#(w, pos, rest))
    [Positioned(token.QuotedIdent(w), pos, _), ..rest] -> Ok(#(w, pos, rest))
    [Positioned(t, pos, _), ..] ->
      Error(ParseError(
        "Expected a name, found `" <> token.to_string(t) <> "`",
        pos,
        None,
      ))
    [] -> Error(ParseError("Unexpected end of file, expected a name", 0, None))
  }
}

fn keyword(tokens: Tokens, want: String) -> Result(#(Int, Tokens), Error) {
  case tokens {
    [Positioned(token.Word(w), pos, _), ..rest] ->
      case string.lowercase(w) == want {
        True -> Ok(#(pos, rest))
        False ->
          Error(ParseError(
            "Expected `" <> want <> "`, found `" <> w <> "`",
            pos,
            None,
          ))
      }
    [Positioned(t, pos, _), ..] ->
      Error(ParseError(
        "Expected `" <> want <> "`, found `" <> token.to_string(t) <> "`",
        pos,
        None,
      ))
    [] ->
      Error(ParseError(
        "Unexpected end of file, expected `" <> want <> "`",
        0,
        None,
      ))
  }
}

fn expect(
  tokens: Tokens,
  want: token.Token,
  label: String,
) -> Result(#(Int, Tokens), Error) {
  case tokens {
    [Positioned(t, pos, _), ..rest] if t == want -> Ok(#(pos, rest))
    [Positioned(t, pos, _), ..] ->
      Error(ParseError(
        "Expected `" <> label <> "`, found `" <> token.to_string(t) <> "`",
        pos,
        None,
      ))
    [] ->
      Error(ParseError(
        "Unexpected end of file, expected `" <> label <> "`",
        0,
        None,
      ))
  }
}
