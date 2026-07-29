import gleam/list
import glsql/ast
import glsql/error
import glsql/lexer
import glsql/parser

fn parse_one(sql: String) -> ast.Table {
  let assert Ok(tokens) = lexer.lex(sql)
  let assert Ok(ast.SchemaAst([table])) = parser.parse(tokens)
  table
}

fn parse(sql: String) -> Result(ast.SchemaAst, error.Error) {
  let assert Ok(tokens) = lexer.lex(sql)
  parser.parse(tokens)
}

pub fn not_null_test() {
  let table = parse_one("create table t (a text not null);")
  let assert [col] = table.columns
  assert list.any(col.constraints, fn(c) {
    case c {
      ast.NotNull(_) -> True
      _ -> False
    }
  })
}

pub fn inline_primary_key_test() {
  let table = parse_one("create table t (a text primary key);")
  let assert [col] = table.columns
  assert list.any(col.constraints, fn(c) {
    case c {
      ast.PrimaryKey(_) -> True
      _ -> False
    }
  })
}

pub fn default_expression_test() {
  let table = parse_one("create table t (a timestamptz default now());")
  let assert [col] = table.columns
  let assert [ast.Default(expr, _)] =
    list.filter(col.constraints, fn(c) {
      case c {
        ast.Default(_, _) -> True
        _ -> False
      }
    })
  assert expr == "now()"
}

pub fn default_with_nested_parens_test() {
  let table = parse_one("create table t (a int default (1 + (2 * 3)));")
  let assert [col] = table.columns
  assert list.length(col.constraints) == 1
}

pub fn inline_references_test() {
  let table = parse_one("create table t (a uuid references users(id));")
  let assert [col] = table.columns
  let assert [ast.References(tbl, cols, _)] =
    list.filter(col.constraints, fn(c) {
      case c {
        ast.References(_, _, _) -> True
        _ -> False
      }
    })
  assert tbl == "users"
  assert cols == ["id"]
}

pub fn column_check_is_opaque_test() {
  let table = parse_one("create table t (a int check (a > 0));")
  let assert [col] = table.columns
  assert list.length(col.constraints) == 1
}

pub fn table_primary_key_test() {
  let table = parse_one("create table t (a text, b text, primary key (a, b));")
  assert list.length(table.columns) == 2
  let assert [ast.TablePrimaryKey(cols, _)] = table.constraints
  assert cols == ["a", "b"]
}

pub fn table_foreign_key_test() {
  let table =
    parse_one("create table t (a uuid, foreign key (a) references users (id));")
  let assert [ast.TableForeignKey(cols, tbl, ref, _)] = table.constraints
  assert cols == ["a"]
  assert tbl == "users"
  assert ref == ["id"]
}

pub fn named_table_constraint_test() {
  let table =
    parse_one("create table t (a text, constraint t_pk primary key (a));")
  let assert [ast.TablePrimaryKey(cols, _)] = table.constraints
  assert cols == ["a"]
}

pub fn combined_constraints_test() {
  let table =
    parse_one(
      "create table t (id uuid primary key default gen_random_uuid() not null);",
    )
  let assert [col] = table.columns
  assert list.length(col.constraints) == 3
}

pub fn misspelled_constraint_is_error_test() {
  let assert Error(error.ParseError(_, _, _)) =
    parse("create table t (a text not nul);")
}

pub fn unknown_constraint_word_is_error_test() {
  let assert Error(_) = parse("create table t (a text bogus);")
}
