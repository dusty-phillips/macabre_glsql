import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import glsql/internal/ast
import glsql/internal/config.{type Config}
import glsql/internal/dialect/postgres
import glsql/internal/error.{type Error, UnknownType}
import glsql/internal/mapping.{type TypeMapping}
import glsql/internal/suggest

pub type ResolvedSchema {
  ResolvedSchema(tables: List(ResolvedTable))
}

pub type ResolvedTable {
  ResolvedTable(
    sql_name: String,
    module_name: String,
    type_name: String,
    columns: List(ResolvedColumn),
  )
}

pub type ResolvedColumn {
  ResolvedColumn(
    sql_name: String,
    field_name: String,
    gleam_type: String,
    decoder: String,
    encoder: String,
    sql_type_name: String,
    nullable: Bool,
    primary_key: Bool,
    imports: List(String),
  )
}

pub fn resolve(
  schema: ast.SchemaAst,
  cfg: Config,
) -> Result(ResolvedSchema, List(Error)) {
  let results = list.map(schema.tables, resolve_table(_, cfg))
  let errors =
    list.flat_map(results, fn(r) {
      case r {
        Error(errs) -> errs
        Ok(_) -> []
      }
    })

  case errors {
    [] -> Ok(ResolvedSchema(tables: list.filter_map(results, fn(r) { r })))
    _ -> Error(errors)
  }
}

fn resolve_table(
  table: ast.Table,
  cfg: Config,
) -> Result(ResolvedTable, List(Error)) {
  let naming = dict.get(cfg.table_names, table.name)

  let module_name = case naming {
    Ok(config.TableNaming(Some(m), _)) -> m
    _ -> snake_case(table.name)
  }

  let type_name = case naming {
    Ok(config.TableNaming(_, Some(t))) -> t
    _ -> pascal_case(table.name)
  }

  let results = list.map(table.columns, resolve_column(_, table, cfg))
  let errors =
    list.flat_map(results, fn(r) {
      case r {
        Error(e) -> [e]
        Ok(_) -> []
      }
    })

  case errors {
    [] ->
      Ok(ResolvedTable(
        sql_name: table.name,
        module_name: module_name,
        type_name: type_name,
        columns: list.filter_map(results, fn(r) { r }),
      ))
    _ -> Error(errors)
  }
}

fn resolve_column(
  column: ast.Column,
  table: ast.Table,
  cfg: Config,
) -> Result(ResolvedColumn, Error) {
  let type_name = string.lowercase(column.sql_type.name)
  use base <- result.try(lookup_type(type_name, column.sql_type.pos, cfg))

  let primary_key = has_primary_key(column)
  let nullable = is_nullable(column, primary_key)

  let #(gleam_type, decoder, encoder) = case column.sql_type.array_dims > 0 {
    True -> #(
      "List(" <> base.gleam_type <> ")",
      "decode.list(" <> base.decoder <> ")",
      base.encoder,
    )
    False -> #(base.gleam_type, base.decoder, base.encoder)
  }

  let #(gleam_type, decoder) = case nullable {
    True -> #(
      "Option(" <> gleam_type <> ")",
      "decode.optional(" <> decoder <> ")",
    )
    False -> #(gleam_type, decoder)
  }

  let field_name = case
    dict.get(cfg.renames, table.name <> "." <> column.name)
  {
    Ok(new_name) -> new_name
    Error(Nil) -> snake_case(column.name)
  }

  Ok(ResolvedColumn(
    sql_name: column.name,
    field_name: field_name,
    gleam_type: gleam_type,
    decoder: decoder,
    encoder: encoder,
    sql_type_name: type_name,
    nullable: nullable,
    primary_key: primary_key,
    imports: base.imports,
  ))
}

fn lookup_type(
  name: String,
  pos: Int,
  cfg: Config,
) -> Result(TypeMapping, Error) {
  let builtins = postgres.builtin_types()
  case dict.get(cfg.types, name) {
    Ok(m) -> Ok(m)
    Error(Nil) ->
      case dict.get(builtins, name) {
        Ok(m) -> Ok(m)
        Error(Nil) -> {
          let candidates =
            list.append(dict.keys(builtins), dict.keys(cfg.types))
          Error(UnknownType(name, pos, suggest.closest(name, candidates)))
        }
      }
  }
}

fn has_primary_key(column: ast.Column) -> Bool {
  list.any(column.constraints, fn(c) {
    case c {
      ast.PrimaryKey(_) -> True
      _ -> False
    }
  })
}

fn is_nullable(column: ast.Column, primary_key: Bool) -> Bool {
  let not_null =
    list.any(column.constraints, fn(c) {
      case c {
        ast.NotNull(_) -> True
        _ -> False
      }
    })

  let serial =
    list.contains(
      ["serial", "bigserial", "smallserial"],
      string.lowercase(column.sql_type.name),
    )

  !{ not_null || primary_key || serial }
}

pub fn snake_case(name: String) -> String {
  name
  |> string.lowercase
  |> string.replace(" ", "_")
  |> string.replace("-", "_")
}

pub fn pascal_case(name: String) -> String {
  snake_case(name)
  |> string.split("_")
  |> list.map(capitalise)
  |> string.join("")
}

fn capitalise(word: String) -> String {
  case string.pop_grapheme(word) {
    Ok(#(first, rest)) -> string.uppercase(first) <> rest
    Error(Nil) -> word
  }
}
