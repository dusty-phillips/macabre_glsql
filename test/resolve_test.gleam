import gleam/dict
import gleam/option
import glsql/internal/config
import glsql/internal/error
import glsql/internal/lexer
import glsql/internal/mapping
import glsql/internal/parser
import glsql/internal/resolve

fn run(sql: String, cfg: config.Config) {
  let assert Ok(tokens) = lexer.lex(sql)
  let assert Ok(schema) = parser.parse(tokens)
  resolve.resolve(schema, cfg)
}

fn default_run(sql: String) {
  run(sql, config.default())
}

pub fn resolves_text_column_test() {
  let assert Ok(r) = default_run("create table users (name text not null);")
  let assert [table] = r.tables
  assert table.sql_name == "users"
  assert table.module_name == "users"
  assert table.type_name == "Users"
  let assert [col] = table.columns
  assert col.field_name == "name"
  assert col.gleam_type == "String"
  assert col.decoder == "decode.string"
  assert col.nullable == False
}

pub fn nullable_wraps_in_option_test() {
  let assert Ok(r) = default_run("create table t (bio text);")
  let assert [table] = r.tables
  let assert [col] = table.columns
  assert col.nullable == True
  assert col.gleam_type == "Option(String)"
  assert col.decoder == "decode.optional(decode.string)"
}

pub fn primary_key_is_not_null_test() {
  let assert Ok(r) = default_run("create table t (id uuid primary key);")
  let assert [table] = r.tables
  let assert [col] = table.columns
  assert col.nullable == False
  assert col.primary_key == True
}

pub fn serial_is_not_null_test() {
  let assert Ok(r) = default_run("create table t (id serial);")
  let assert [table] = r.tables
  let assert [col] = table.columns
  assert col.gleam_type == "Int"
}

pub fn unknown_type_is_error_test() {
  let assert Error([error.UnknownType(name, _, _)]) =
    default_run("create table t (a wombat);")
  assert name == "wombat"
}

// `txt` is one edit from `text` and further from every other builtin, so the
// suggestion does not depend on which order the builtins happen to be in.
pub fn unknown_type_suggests_close_match_test() {
  let assert Error([error.UnknownType(_, _, hint)]) =
    default_run("create table t (a txt);")
  assert hint == option.Some("text")
}

pub fn range_type_reports_how_to_map_it_test() {
  let assert Error([error.UnmappedType(name, _)]) =
    default_run("create table t (stay daterange);")
  assert name == "daterange"
}

pub fn unmapped_type_gets_no_did_you_mean_hint_test() {
  // `interval` is close to nothing useful, and suggesting a near-miss name
  // would send people down the wrong path.
  let assert Error([error.UnmappedType(_, _)]) =
    default_run("create table t (span interval);")
}

pub fn unmapped_type_can_be_mapped_from_config_test() {
  let cfg =
    config.Config(
      ..config.default(),
      types: dict.from_list([
        #(
          "daterange",
          mapping.TypeMapping(
            gleam_type: "String",
            decoder: "decode.string",
            encoder: "pog.text($)",
            imports: [],
          ),
        ),
      ]),
    )
  let assert Ok(r) = run("create table t (stay daterange not null);", cfg)
  let assert [table] = r.tables
  let assert [col] = table.columns
  assert col.gleam_type == "String"
}

pub fn custom_type_from_config_test() {
  let cfg =
    config.Config(
      ..config.default(),
      types: dict.from_list([
        #(
          "timestamptz",
          mapping.TypeMapping(
            gleam_type: "timestamp.Timestamp",
            decoder: "ts.decoder()",
            encoder: "pog.text(ts.to_rfc3339($))",
            imports: ["gleam/time/timestamp"],
          ),
        ),
      ]),
    )
  let assert Ok(r) = run("create table t (at timestamptz not null);", cfg)
  let assert [table] = r.tables
  let assert [col] = table.columns
  assert col.gleam_type == "timestamp.Timestamp"
}

pub fn rename_applies_to_field_only_test() {
  let cfg =
    config.Config(
      ..config.default(),
      renames: dict.from_list([#("t.type", "kind")]),
    )
  let assert Ok(r) = run("create table t (type text not null);", cfg)
  let assert [table] = r.tables
  let assert [col] = table.columns
  assert col.field_name == "kind"
  assert col.sql_name == "type"
}

pub fn bare_rename_applies_to_every_table_test() {
  let cfg =
    config.Config(
      ..config.default(),
      renames: dict.from_list([#("type", "kind")]),
    )
  let assert Ok(r) =
    run("create table a (type text not null); create table b (type text);", cfg)
  let assert [table_a, table_b] = r.tables
  let assert [col_a] = table_a.columns
  let assert [col_b] = table_b.columns
  assert col_a.field_name == "kind"
  assert col_b.field_name == "kind"
  assert col_a.sql_name == "type"
}

pub fn qualified_rename_wins_over_bare_rename_test() {
  let cfg =
    config.Config(
      ..config.default(),
      renames: dict.from_list([#("type", "kind"), #("b.type", "b_kind")]),
    )
  let assert Ok(r) =
    run("create table a (type text not null); create table b (type text);", cfg)
  let assert [table_a, table_b] = r.tables
  let assert [col_a] = table_a.columns
  let assert [col_b] = table_b.columns
  assert col_a.field_name == "kind"
  assert col_b.field_name == "b_kind"
}

pub fn bare_rename_does_not_touch_other_columns_test() {
  let cfg =
    config.Config(
      ..config.default(),
      renames: dict.from_list([#("type", "kind")]),
    )
  let assert Ok(r) = run("create table a (name text not null);", cfg)
  let assert [table] = r.tables
  let assert [col] = table.columns
  assert col.field_name == "name"
}

pub fn table_naming_override_test() {
  let cfg =
    config.Config(
      ..config.default(),
      table_names: dict.from_list([
        #("users", config.TableNaming(option.Some("user"), option.Some("User"))),
      ]),
    )
  let assert Ok(r) = run("create table users (id text not null);", cfg)
  let assert [table] = r.tables
  assert table.module_name == "user"
  assert table.type_name == "User"
}

pub fn array_type_is_list_test() {
  let assert Ok(r) = default_run("create table t (tags text[] not null);")
  let assert [table] = r.tables
  let assert [col] = table.columns
  assert col.gleam_type == "List(String)"
}
