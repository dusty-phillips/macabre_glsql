import gleam/string
import glsql/internal/codegen
import glsql/internal/config
import glsql/internal/lexer
import glsql/internal/parser
import glsql/internal/resolve
import simplifile

fn generate(sql: String) -> String {
  let assert Ok(tokens) = lexer.lex(sql)
  let assert Ok(schema) = parser.parse(tokens)
  let assert Ok(r) = resolve.resolve(schema, config.default())
  let assert [table] = r.tables
  codegen.generate_table(table, "pog", "priv/schema.sql", "db/glsql_schema")
}

pub fn generates_record_test() {
  let out = generate("create table users (id text not null, bio text);")
  assert string.contains(out, "pub type Users {")
  assert string.contains(out, "id: String")
  assert string.contains(out, "bio: Option(String)")
}

pub fn generates_table_constant_test() {
  let out = generate("create table users (id text not null);")
  assert string.contains(out, "pub const table: String = \"users\"")
}

pub fn generates_columns_constant_test() {
  let out = generate("create table users (id text not null, bio text);")
  assert string.contains(out, "pub const columns: String = \"id, bio\"")
}

pub fn generates_positional_decoder_test() {
  let out = generate("create table users (id text not null, bio text);")
  assert string.contains(out, "use id <- decode.field(0, decode.string)")
  assert string.contains(
    out,
    "use bio <- decode.field(1, decode.optional(decode.string))",
  )
  assert string.contains(out, "decode.success(Users(id:, bio:))")
}

pub fn generates_encoder_test() {
  let out = generate("create table users (id text not null);")
  assert string.contains(out, "pub fn to_params(row: Users)")
  assert string.contains(out, "pog.text(row.id)")
}

pub fn generates_column_metadata_test() {
  let out = generate("create table users (id text primary key);")
  assert string.contains(
    out,
    "pub fn col_id() -> Column(String) {\n  Column(\"users\", \"id\", \"text\", False, True, decode.string)\n}",
  )
}

pub fn includes_do_not_edit_header_test() {
  let out = generate("create table users (id text not null);")
  assert string.contains(out, "Do not edit")
  assert string.contains(out, "priv/schema.sql")
}

pub fn omits_option_import_when_unused_test() {
  let out = generate("create table users (id text not null);")
  assert !string.contains(out, "import gleam/option")
}

pub fn golden_users_test() {
  let out =
    generate(
      "create table users (id uuid primary key, name text not null, bio text);",
    )
  let assert Ok(expected) = simplifile.read("test/golden/users.gleam.txt")
  assert out == expected
}
