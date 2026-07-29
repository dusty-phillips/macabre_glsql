import gleam/option.{None}
import glsql/internal/ast
import glsql/internal/error
import glsql/internal/lexer
import glsql/internal/parser

fn parse(sql: String) -> Result(ast.SchemaAst, error.Error) {
  let assert Ok(tokens) = lexer.lex(sql)
  parser.parse(tokens)
}

pub fn parse_single_column_test() {
  let assert Ok(ast.SchemaAst([table])) = parse("create table users (id text);")
  assert table.name == "users"
  assert table.schema == None
  let assert [col] = table.columns
  assert col.name == "id"
  assert col.sql_type.name == "text"
}

pub fn parse_is_case_insensitive_test() {
  let assert Ok(ast.SchemaAst([table])) = parse("CREATE TABLE Users (Id TEXT);")
  assert table.name == "Users"
  let assert [col] = table.columns
  assert col.name == "Id"
  assert col.sql_type.name == "TEXT"
}

pub fn parse_multiple_columns_test() {
  let assert Ok(ast.SchemaAst([table])) =
    parse("create table users (id text, name text, email text);")
  assert list_names(table.columns) == ["id", "name", "email"]
}

fn list_names(columns: List(ast.Column)) -> List(String) {
  case columns {
    [] -> []
    [c, ..rest] -> [c.name, ..list_names(rest)]
  }
}

pub fn parse_multiple_tables_test() {
  let assert Ok(ast.SchemaAst([a, b])) =
    parse("create table a (x text); create table b (y text);")
  assert a.name == "a"
  assert b.name == "b"
}

pub fn parse_if_not_exists_test() {
  let assert Ok(ast.SchemaAst([table])) =
    parse("create table if not exists users (id text);")
  assert table.name == "users"
}

pub fn parse_schema_qualified_test() {
  let assert Ok(ast.SchemaAst([table])) =
    parse("create table public.users (id text);")
  assert table.name == "users"
  assert table.schema == option.Some("public")
}

pub fn parse_quoted_names_test() {
  let assert Ok(ast.SchemaAst([table])) =
    parse("create table \"user table\" (\"my col\" text);")
  assert table.name == "user table"
  let assert [col] = table.columns
  assert col.name == "my col"
}

pub fn parse_type_with_precision_test() {
  let assert Ok(ast.SchemaAst([table])) =
    parse("create table t (amount numeric(10,2));")
  let assert [col] = table.columns
  assert col.sql_type.name == "numeric"
  assert col.sql_type.args == ["10", "2"]
}

pub fn parse_character_varying_with_precision_test() {
  let assert Ok(ast.SchemaAst([table])) =
    parse("create table t (id character varying(255) not null);")
  let assert [col] = table.columns
  assert col.sql_type.name == "character varying"
  assert col.sql_type.args == ["255"]
}

pub fn parse_character_varying_without_precision_test() {
  let assert Ok(ast.SchemaAst([table])) =
    parse("create table t (bio character varying not null);")
  let assert [col] = table.columns
  assert col.sql_type.name == "character varying"
  assert col.sql_type.args == []
}

pub fn parse_double_precision_test() {
  let assert Ok(ast.SchemaAst([table])) =
    parse("create table t (score double precision not null);")
  let assert [col] = table.columns
  assert col.sql_type.name == "double precision"
}

pub fn parse_array_type_test() {
  let assert Ok(ast.SchemaAst([table])) = parse("create table t (tags text[]);")
  let assert [col] = table.columns
  assert col.sql_type.name == "text"
  assert col.sql_type.array_dims == 1
}

pub fn parse_missing_paren_is_error_test() {
  let assert Error(_) = parse("create table users (")
}

pub fn parse_empty_input_test() {
  let assert Ok(ast.SchemaAst([])) = parse("")
}
