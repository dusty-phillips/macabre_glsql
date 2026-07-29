import gleam/dict
import gleam/list
import gleam/option.{None}
import gleam/set
import gleam/string
import glsql/ast
import glsql/config.{type Config}
import glsql/error.{type Error, ValidationError}

pub const reserved_words = [
  "as", "assert", "auto", "case", "const", "delegate", "derive", "echo", "else",
  "fn", "if", "implement", "import", "let", "macro", "opaque", "panic", "pub",
  "test", "todo", "type", "use",
]

pub fn check(schema: ast.SchemaAst, cfg: Config) -> Result(Nil, List(Error)) {
  let errors =
    list.flatten([
      duplicate_tables(schema.tables),
      list.flat_map(schema.tables, fn(t) { check_table(t, schema, cfg) }),
    ])

  case errors {
    [] -> Ok(Nil)
    _ -> Error(errors)
  }
}

fn check_table(
  table: ast.Table,
  schema: ast.SchemaAst,
  cfg: Config,
) -> List(Error) {
  list.flatten([
    duplicate_columns(table),
    multiple_primary_keys(table),
    empty_names(table),
    reserved_names(table, cfg),
    foreign_keys(table, schema),
  ])
}

fn duplicate_tables(tables: List(ast.Table)) -> List(Error) {
  let #(errors, _) =
    list.fold(tables, #([], set.new()), fn(state, t) {
      let #(errors, seen) = state
      let key = string.lowercase(t.name)
      case set.contains(seen, key) {
        True -> #(
          [
            ValidationError(
              "The table `" <> t.name <> "` is defined more than once",
              t.pos,
              None,
            ),
            ..errors
          ],
          seen,
        )
        False -> #(errors, set.insert(seen, key))
      }
    })
  list.reverse(errors)
}

fn duplicate_columns(table: ast.Table) -> List(Error) {
  let #(errors, _) =
    list.fold(table.columns, #([], set.new()), fn(state, c) {
      let #(errors, seen) = state
      let key = string.lowercase(c.name)
      case set.contains(seen, key) {
        True -> #(
          [
            ValidationError(
              "`" <> table.name <> "` has two columns named `" <> c.name <> "`",
              c.pos,
              None,
            ),
            ..errors
          ],
          seen,
        )
        False -> #(errors, set.insert(seen, key))
      }
    })
  list.reverse(errors)
}

fn multiple_primary_keys(table: ast.Table) -> List(Error) {
  let inline =
    list.filter(table.columns, fn(c) {
      list.any(c.constraints, fn(k) {
        case k {
          ast.PrimaryKey(_) -> True
          _ -> False
        }
      })
    })

  let table_level =
    list.filter(table.constraints, fn(k) {
      case k {
        ast.TablePrimaryKey(_, _) -> True
        _ -> False
      }
    })

  case list.length(inline) + list.length(table_level) > 1 {
    True -> [
      ValidationError(
        "`" <> table.name <> "` declares more than one primary key",
        table.pos,
        None,
      ),
    ]
    False -> []
  }
}

fn empty_names(table: ast.Table) -> List(Error) {
  let table_errors = case string.trim(table.name) == "" {
    True -> [ValidationError("This table has an empty name", table.pos, None)]
    False -> []
  }
  let column_errors =
    list.filter_map(table.columns, fn(c) {
      case string.trim(c.name) == "" {
        True ->
          Ok(ValidationError("This column has an empty name", c.pos, None))
        False -> Error(Nil)
      }
    })
  list.append(table_errors, column_errors)
}

fn reserved_names(table: ast.Table, cfg: Config) -> List(Error) {
  list.filter_map(table.columns, fn(c) {
    let key = table.name <> "." <> c.name
    let renamed = dict.has_key(cfg.renames, key)
    case list.contains(reserved_words, string.lowercase(c.name)) && !renamed {
      True ->
        Ok(ValidationError(
          "`"
            <> c.name
            <> "` is a reserved word in Gleam, so it cannot be a field name. "
            <> "Add a rename to glsql.toml:\n\n    [rename]\n    \""
            <> key
            <> "\" = \""
            <> c.name
            <> "_\"",
          c.pos,
          None,
        ))
      False -> Error(Nil)
    }
  })
}

fn foreign_keys(table: ast.Table, schema: ast.SchemaAst) -> List(Error) {
  let inline =
    list.flat_map(table.columns, fn(c) {
      list.filter_map(c.constraints, fn(k) {
        case k {
          ast.References(t, cols, pos) -> Ok(#(t, cols, pos))
          _ -> Error(Nil)
        }
      })
    })

  let table_level =
    list.filter_map(table.constraints, fn(k) {
      case k {
        ast.TableForeignKey(_, t, cols, pos) -> Ok(#(t, cols, pos))
        _ -> Error(Nil)
      }
    })

  list.append(inline, table_level)
  |> list.flat_map(fn(fk) {
    let #(ref_table, ref_cols, pos) = fk
    case find_table(schema, ref_table) {
      Error(Nil) -> [
        ValidationError(
          "`" <> ref_table <> "` is not a table in this schema",
          pos,
          None,
        ),
      ]
      Ok(target) ->
        list.filter_map(ref_cols, fn(col) {
          case has_column(target, col) {
            True -> Error(Nil)
            False ->
              Ok(ValidationError(
                "`" <> ref_table <> "` has no column `" <> col <> "`",
                pos,
                None,
              ))
          }
        })
    }
  })
}

fn find_table(schema: ast.SchemaAst, name: String) -> Result(ast.Table, Nil) {
  list.find(schema.tables, fn(t) {
    string.lowercase(t.name) == string.lowercase(name)
  })
}

fn has_column(table: ast.Table, name: String) -> Bool {
  list.any(table.columns, fn(c) {
    string.lowercase(c.name) == string.lowercase(name)
  })
}
