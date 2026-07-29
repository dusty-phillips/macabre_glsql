import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import glsql/internal/ast
import glsql/internal/error.{type Error, ParseError}
import glsql/internal/suggest
import glsql/internal/token.{type Positioned, Positioned}

type Tokens =
  List(Positioned)

const constraint_keywords = [
  "not", "null", "primary", "unique", "default", "references", "check",
  "constraint", "foreign", "generated", "collate",
]

/// Leading keywords of statements we deliberately ignore.
const ignored_statements = [
  "alter", "drop", "set", "comment", "grant", "revoke", "begin", "commit",
  "insert", "update", "delete", "select", "truncate", "analyze", "vacuum",
  "refresh", "reset", "with",
]

/// Second keyword of a `create ...` statement we deliberately ignore.
const ignored_create_objects = [
  "index", "unique", "extension", "sequence", "view", "schema", "function",
  "trigger", "type", "domain", "materialized", "publication", "policy",
  "aggregate", "operator", "role", "database",
]

const statement_keywords = ["create", "alter", "drop", "set", "comment"]

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

    // psql meta-commands such as `\c mydb` show up in dumps but are not SQL.
    [Positioned(token.Symbol("\\"), _, _), ..rest] ->
      parse_statements(skip_statement(rest), acc)

    [Positioned(token.Word(w), pos, _), ..rest] ->
      case string.lowercase(w) {
        "create" ->
          case rest {
            [Positioned(token.Word(obj), obj_pos, _), ..after] ->
              case string.lowercase(obj) {
                "table" -> {
                  use #(table, rest) <- result.try(parse_create_table(tokens))
                  parse_statements(rest, [table, ..acc])
                }
                other ->
                  case list.contains(ignored_create_objects, other) {
                    True -> parse_statements(skip_statement(after), acc)
                    False ->
                      Error(error.UnknownStatement(
                        obj,
                        obj_pos,
                        suggest.closest(other, [
                          "table",
                          ..ignored_create_objects
                        ]),
                      ))
                  }
              }
            _ ->
              Error(ParseError(
                "Unexpected end of file after `create`",
                pos,
                None,
              ))
          }

        other ->
          case list.contains(ignored_statements, other) {
            True -> parse_statements(skip_statement(rest), acc)
            False ->
              Error(error.UnknownStatement(
                w,
                pos,
                suggest.closest(other, statement_keywords),
              ))
          }
      }

    [Positioned(t, pos, _), ..] ->
      Error(ParseError(
        "Expected a statement, found `" <> token.to_string(t) <> "`",
        pos,
        None,
      ))
  }
}

/// Consume tokens up to and including the next top-level `;`.
fn skip_statement(tokens: Tokens) -> Tokens {
  case tokens {
    [] -> []
    [Positioned(token.Semicolon, _, _), ..rest] -> rest
    [_, ..rest] -> skip_statement(rest)
  }
}

fn parse_create_table(tokens: Tokens) -> Result(#(ast.Table, Tokens), Error) {
  use #(pos, rest) <- result.try(keyword(tokens, "create"))
  use #(_, rest) <- result.try(keyword(rest, "table"))
  let rest = skip_if_not_exists(rest)
  use #(schema, name, rest) <- result.try(qualified_name(rest))
  use #(_, rest) <- result.try(expect(rest, token.LParen, "("))
  use #(columns, constraints, rest) <- result.try(parse_column_list(rest, []))
  use #(_, rest) <- result.try(expect(rest, token.RParen, ")"))
  // Anything after the closing paren is a table option that does not affect
  // the generated code, such as `PARTITION BY RANGE (...)`, `WITH (...)`,
  // `INHERITS (...)` or `TABLESPACE ...`.
  let rest = skip_statement(rest)
  Ok(#(
    ast.Table(
      name: name,
      schema: schema,
      columns: list.reverse(columns),
      constraints: constraints,
      pos: pos,
    ),
    rest,
  ))
}

fn parse_column_list(
  tokens: Tokens,
  acc: List(ast.Column),
) -> Result(#(List(ast.Column), List(ast.TableConstraint), Tokens), Error) {
  case is_table_constraint(tokens) {
    True -> {
      use #(constraints, rest) <- result.try(
        parse_table_constraints(tokens, []),
      )
      Ok(#(acc, constraints, rest))
    }
    False -> {
      use #(column, rest) <- result.try(parse_column(tokens))
      case rest {
        [Positioned(token.Comma, _, _), ..rest] ->
          parse_column_list(rest, [column, ..acc])
        _ -> Ok(#([column, ..acc], [], rest))
      }
    }
  }
}

fn is_table_constraint(tokens: Tokens) -> Bool {
  case tokens {
    [Positioned(token.Word(w), _, _), ..] ->
      case string.lowercase(w) {
        "primary" | "unique" | "foreign" | "check" | "constraint" -> True
        _ -> False
      }
    _ -> False
  }
}

fn parse_column(tokens: Tokens) -> Result(#(ast.Column, Tokens), Error) {
  use #(name, pos, rest) <- result.try(identifier(tokens))
  use #(sql_type, rest) <- result.try(parse_type(rest))
  use #(constraints, rest) <- result.try(parse_column_constraints(rest, []))
  Ok(#(
    ast.Column(
      name: name,
      sql_type: sql_type,
      constraints: list.reverse(constraints),
      pos: pos,
    ),
    rest,
  ))
}

fn parse_column_constraints(
  tokens: Tokens,
  acc: List(ast.ColumnConstraint),
) -> Result(#(List(ast.ColumnConstraint), Tokens), Error) {
  case tokens {
    [Positioned(token.Comma, _, _), ..] -> Ok(#(acc, tokens))
    [Positioned(token.RParen, _, _), ..] -> Ok(#(acc, tokens))
    [] -> Ok(#(acc, tokens))

    [Positioned(token.Word(w), pos, _), ..rest] ->
      case string.lowercase(w) {
        "not" -> {
          use #(_, rest) <- result.try(keyword(rest, "null"))
          parse_column_constraints(rest, [ast.NotNull(pos), ..acc])
        }
        "null" -> parse_column_constraints(rest, [ast.Nullable(pos), ..acc])
        "primary" -> {
          use #(_, rest) <- result.try(keyword(rest, "key"))
          parse_column_constraints(rest, [ast.PrimaryKey(pos), ..acc])
        }
        "unique" -> parse_column_constraints(rest, [ast.Unique(pos), ..acc])
        "default" -> {
          let #(expr, rest) = take_expression(rest, "", 0)
          parse_column_constraints(rest, [ast.Default(expr, pos), ..acc])
        }
        "check" -> {
          let #(expr, rest) = take_expression(rest, "", 0)
          parse_column_constraints(rest, [ast.Check(expr, pos), ..acc])
        }
        "references" -> {
          use #(_schema, tbl, rest) <- result.try(qualified_name(rest))
          use #(cols, rest) <- result.try(optional_column_list(rest))
          parse_column_constraints(rest, [ast.References(tbl, cols, pos), ..acc])
        }
        // `GENERATED ALWAYS AS (expr) STORED` and the `AS IDENTITY` forms all
        // mean the database supplies the value, same as a default.
        "generated" -> {
          let rest = skip_words(rest, ["always", "by", "default"])
          use #(_, rest) <- result.try(keyword(rest, "as"))
          let #(expr, rest) = generated_value(rest)
          parse_column_constraints(rest, [ast.Default(expr, pos), ..acc])
        }
        // A collation does not change the Gleam type.
        "collate" -> {
          use #(_name, _, rest) <- result.try(identifier(rest))
          parse_column_constraints(rest, acc)
        }
        other ->
          Error(ParseError(
            "Unknown column constraint `" <> w <> "`",
            pos,
            suggest.closest(other, constraint_keywords),
          ))
      }

    [Positioned(t, pos, _), ..] ->
      Error(ParseError(
        "Unexpected `" <> token.to_string(t) <> "` in column definition",
        pos,
        None,
      ))
  }
}

fn parse_table_constraints(
  tokens: Tokens,
  acc: List(ast.TableConstraint),
) -> Result(#(List(ast.TableConstraint), Tokens), Error) {
  let tokens = skip_constraint_name(tokens)
  case tokens {
    [Positioned(token.Word(w), pos, _), ..rest] ->
      case string.lowercase(w) {
        "primary" -> {
          use #(_, rest) <- result.try(keyword(rest, "key"))
          use #(cols, rest) <- result.try(optional_column_list(rest))
          continue_table_constraints(rest, [
            ast.TablePrimaryKey(cols, pos),
            ..acc
          ])
        }
        "unique" -> {
          use #(cols, rest) <- result.try(optional_column_list(rest))
          continue_table_constraints(rest, [ast.TableUnique(cols, pos), ..acc])
        }
        "foreign" -> {
          use #(_, rest) <- result.try(keyword(rest, "key"))
          use #(cols, rest) <- result.try(optional_column_list(rest))
          use #(_, rest) <- result.try(keyword(rest, "references"))
          use #(_schema, tbl, rest) <- result.try(qualified_name(rest))
          use #(ref, rest) <- result.try(optional_column_list(rest))
          continue_table_constraints(rest, [
            ast.TableForeignKey(cols, tbl, ref, pos),
            ..acc
          ])
        }
        "check" -> {
          let #(expr, rest) = take_expression(rest, "", 0)
          continue_table_constraints(rest, [ast.TableCheck(expr, pos), ..acc])
        }
        other ->
          Error(ParseError(
            "Unknown table constraint `" <> w <> "`",
            pos,
            suggest.closest(other, constraint_keywords),
          ))
      }
    [Positioned(t, pos, _), ..] ->
      Error(ParseError(
        "Expected a table constraint, found `" <> token.to_string(t) <> "`",
        pos,
        None,
      ))
    [] ->
      Error(ParseError("Unexpected end of file in table constraints", 0, None))
  }
}

fn continue_table_constraints(
  tokens: Tokens,
  acc: List(ast.TableConstraint),
) -> Result(#(List(ast.TableConstraint), Tokens), Error) {
  case tokens {
    [Positioned(token.Comma, _, _), ..rest] ->
      parse_table_constraints(rest, acc)
    _ -> Ok(#(list.reverse(acc), tokens))
  }
}

fn skip_constraint_name(tokens: Tokens) -> Tokens {
  case tokens {
    [Positioned(token.Word(w), _, _), ..rest] ->
      case string.lowercase(w) {
        "constraint" ->
          case rest {
            [Positioned(token.Word(_), _, _), ..rest] -> rest
            [Positioned(token.QuotedIdent(_), _, _), ..rest] -> rest
            _ -> rest
          }
        _ -> tokens
      }
    _ -> tokens
  }
}

fn optional_column_list(
  tokens: Tokens,
) -> Result(#(List(String), Tokens), Error) {
  case tokens {
    [Positioned(token.LParen, _, _), ..rest] -> collect_names(rest, [])
    _ -> Ok(#([], tokens))
  }
}

fn collect_names(
  tokens: Tokens,
  acc: List(String),
) -> Result(#(List(String), Tokens), Error) {
  use #(name, _pos, rest) <- result.try(identifier(tokens))
  case rest {
    [Positioned(token.Comma, _, _), ..rest] ->
      collect_names(rest, [name, ..acc])
    [Positioned(token.RParen, _, _), ..rest] ->
      Ok(#(list.reverse([name, ..acc]), rest))
    [Positioned(t, pos, _), ..] ->
      Error(ParseError(
        "Expected `,` or `)`, found `" <> token.to_string(t) <> "`",
        pos,
        None,
      ))
    [] -> Error(ParseError("Unexpected end of file in column list", 0, None))
  }
}

/// Consume an expression to a balanced-paren boundary, stopping at a top-level
/// comma or closing paren. Retained as opaque source text — never interpreted.
/// Read what follows `generated ... as`: either `identity`, with optional
/// sequence settings, or a parenthesised expression with an optional
/// `stored` / `virtual` after it.
fn generated_value(tokens: Tokens) -> #(String, Tokens) {
  let identity = case tokens {
    [Positioned(token.Word(w), _, _), ..] -> string.lowercase(w) == "identity"
    _ -> False
  }
  case identity, tokens {
    True, [_, ..rest] -> #("identity", discard_parens(rest))
    _, _ -> {
      let #(expr, rest) = take_parens(tokens)
      #(expr, skip_words(rest, ["stored", "virtual"]))
    }
  }
}

/// Read a balanced `( ... )` group, returning the text inside it.
fn take_parens(tokens: Tokens) -> #(String, Tokens) {
  case tokens {
    [Positioned(token.LParen, _, _), ..rest] -> {
      let #(expr, rest) = take_expression(rest, "", 0)
      case rest {
        [Positioned(token.RParen, _, _), ..rest] -> #(expr, rest)
        _ -> #(expr, rest)
      }
    }
    _ -> take_expression(tokens, "", 0)
  }
}

fn discard_parens(tokens: Tokens) -> Tokens {
  case tokens {
    [Positioned(token.LParen, _, _), ..] -> {
      let #(_, rest) = take_parens(tokens)
      rest
    }
    _ -> tokens
  }
}

/// Drop any of `words` from the front, whatever order they come in.
fn skip_words(tokens: Tokens, words: List(String)) -> Tokens {
  case tokens {
    [Positioned(token.Word(w), _, _), ..rest] ->
      case list.contains(words, string.lowercase(w)) {
        True -> skip_words(rest, words)
        False -> tokens
      }
    _ -> tokens
  }
}

fn take_expression(
  tokens: Tokens,
  acc: String,
  depth: Int,
) -> #(String, Tokens) {
  case tokens {
    [] -> #(string.trim(acc), [])
    [Positioned(token.Comma, _, _), ..] if depth == 0 -> #(
      string.trim(acc),
      tokens,
    )
    [Positioned(token.RParen, _, _), ..] if depth == 0 -> #(
      string.trim(acc),
      tokens,
    )
    [Positioned(token.Word(w), _, _), ..rest] if depth == 0 -> {
      case list.contains(constraint_keywords, string.lowercase(w)) {
        True -> #(string.trim(acc), tokens)
        False -> take_expression(rest, join(acc, w), depth)
      }
    }
    [Positioned(token.LParen, _, _), ..rest] ->
      take_expression(rest, acc <> "(", depth + 1)
    [Positioned(token.RParen, _, _), ..rest] ->
      take_expression(rest, acc <> ")", depth - 1)
    [Positioned(token.Word(w), _, _), ..rest] ->
      take_expression(rest, join(acc, w), depth)
    [Positioned(t, _, _), ..rest] ->
      take_expression(rest, acc <> token.to_string(t), depth)
  }
}

fn join(acc: String, word: String) -> String {
  case acc == "" || string.ends_with(acc, "(") {
    True -> acc <> word
    False -> acc <> " " <> word
  }
}

/// Type names written as several words. Longer names come first so that
/// `timestamp with time zone` wins over a bare `timestamp`.
const multi_word_types = [
  ["timestamp", "with", "time", "zone"],
  ["timestamp", "without", "time", "zone"],
  ["time", "with", "time", "zone"],
  ["time", "without", "time", "zone"],
  ["character", "varying"],
  ["bit", "varying"],
  ["double", "precision"],
]

fn parse_type(tokens: Tokens) -> Result(#(ast.SqlType, Tokens), Error) {
  // A dump can qualify a type with its schema, as in `public.mpaa_rating`.
  // Only the last part is kept, so it can be looked up by its plain name.
  use #(_schema, name, pos, rest) <- result.try(qualified_type_name(tokens))

  // `timestamp(6) without time zone` puts the argument in the middle of the
  // name, so look for arguments both before and after the extra words.
  use #(args, rest) <- result.try(parse_type_args(rest))
  let #(name, rest) = extend_type_name(name, rest)
  use #(args, rest) <- result.try(case args {
    [] -> parse_type_args(rest)
    _ -> Ok(#(args, rest))
  })

  let #(dims, rest) = parse_array_dims(rest, 0)
  Ok(#(ast.SqlType(name: name, args: args, array_dims: dims, pos: pos), rest))
}

fn qualified_type_name(
  tokens: Tokens,
) -> Result(#(Option(String), String, Int, Tokens), Error) {
  use #(first, pos, rest) <- result.try(identifier(tokens))
  case rest {
    [Positioned(token.Dot, _, _), ..rest] -> {
      use #(second, _, rest) <- result.try(identifier(rest))
      Ok(#(Some(first), second, pos, rest))
    }
    _ -> Ok(#(None, first, pos, rest))
  }
}

/// Pull in the remaining words when a type name is spelled with several.
fn extend_type_name(name: String, tokens: Tokens) -> #(String, Tokens) {
  let lowered = string.lowercase(name)
  let candidates =
    list.filter(multi_word_types, fn(words) {
      case words {
        [first, ..] -> first == lowered
        [] -> False
      }
    })
  first_matching_name(name, candidates, tokens)
}

fn first_matching_name(
  name: String,
  candidates: List(List(String)),
  tokens: Tokens,
) -> #(String, Tokens) {
  case candidates {
    [] -> #(name, tokens)
    [words, ..others] -> {
      let wanted = list.drop(words, 1)
      case match_words(wanted, tokens) {
        Ok(rest) -> #(string.join([name, ..wanted], " "), rest)
        Error(Nil) -> first_matching_name(name, others, tokens)
      }
    }
  }
}

fn match_words(words: List(String), tokens: Tokens) -> Result(Tokens, Nil) {
  case words, tokens {
    [], _ -> Ok(tokens)
    [want, ..rest_words], [Positioned(token.Word(w), _, _), ..rest] ->
      case string.lowercase(w) == want {
        True -> match_words(rest_words, rest)
        False -> Error(Nil)
      }
    _, _ -> Error(Nil)
  }
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
    [Positioned(token.LBracket, _, _), Positioned(token.RBracket, _, _), ..rest] ->
      parse_array_dims(rest, count + 1)
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
      case string.lowercase(a), string.lowercase(b), string.lowercase(c) {
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
