import gleam/option
import glsql/internal/ast
import glsql/internal/error
import glsql/internal/lexer
import glsql/internal/parser

fn parse(sql: String) -> Result(ast.SchemaAst, error.Error) {
  let assert Ok(tokens) = lexer.lex(sql)
  parser.parse(tokens)
}

pub fn skips_create_index_test() {
  let assert Ok(ast.SchemaAst([table])) =
    parse("create table t (a text); create index t_a_idx on t (a); ")
  assert table.name == "t"
}

pub fn skips_alter_table_test() {
  let assert Ok(ast.SchemaAst([table])) =
    parse("alter table t add column b text; create table t (a text);")
  assert table.name == "t"
}

pub fn skips_set_and_comment_test() {
  let assert Ok(ast.SchemaAst([_])) =
    parse(
      "set statement_timeout = 0; comment on table t is 'hi'; create table t (a text);",
    )
}

pub fn skips_create_extension_test() {
  let assert Ok(ast.SchemaAst([_])) =
    parse(
      "create extension if not exists \"pgcrypto\"; create table t (a text);",
    )
}

pub fn misspelled_create_is_error_test() {
  let assert Error(error.UnknownStatement(word, _, hint)) =
    parse("craete table users (id text);")
  assert word == "craete"
  assert hint == option.Some("create")
}

pub fn unknown_statement_is_error_test() {
  let assert Error(error.UnknownStatement(_, _, _)) =
    parse("frobnicate the database;")
}

pub fn create_unknown_object_is_error_test() {
  let assert Error(_) = parse("create wombat foo;")
}
