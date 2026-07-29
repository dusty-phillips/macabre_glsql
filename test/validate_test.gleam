import gleam/dict
import gleam/list
import glsql/config
import glsql/error
import glsql/lexer
import glsql/parser
import glsql/validate

fn check(sql: String) -> Result(Nil, List(error.Error)) {
  let assert Ok(tokens) = lexer.lex(sql)
  let assert Ok(schema) = parser.parse(tokens)
  validate.check(schema, config.default())
}

pub fn valid_schema_passes_test() {
  let assert Ok(Nil) = check("create table users (id text, name text);")
}

pub fn duplicate_column_test() {
  let assert Error(errs) = check("create table t (a text, a text);")
  assert list.length(errs) == 1
}

pub fn duplicate_table_test() {
  let assert Error(_) =
    check("create table t (a text); create table t (b text);")
}

pub fn two_primary_keys_test() {
  let assert Error(_) =
    check("create table t (a text primary key, b text primary key);")
}

pub fn missing_fk_table_test() {
  let assert Error(_) = check("create table t (a uuid references nope(id));")
}

pub fn missing_fk_column_test() {
  let assert Error(_) =
    check(
      "create table u (id uuid); create table t (a uuid references u(nope));",
    )
}

pub fn valid_fk_passes_test() {
  let assert Ok(Nil) =
    check("create table u (id uuid); create table t (a uuid references u(id));")
}

pub fn reserved_word_column_test() {
  let assert Error(_) = check("create table t (type text);")
}

pub fn reserved_word_with_rename_passes_test() {
  let assert Ok(tokens) = lexer.lex("create table t (type text);")
  let assert Ok(schema) = parser.parse(tokens)
  let cfg =
    config.Config(
      ..config.default(),
      renames: dict.from_list([#("t.type", "kind")]),
    )
  let assert Ok(Nil) = validate.check(schema, cfg)
}

pub fn reports_all_errors_at_once_test() {
  let assert Error(errs) = check("create table t (a text, a text, type text);")
  assert list.length(errs) >= 2
}
