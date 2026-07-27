import gleam/dict
import gleam/option.{Some}
import glsql/config
import glsql/error

pub fn parse_minimal_test() {
  let assert Ok(c) = config.parse("schema = \"priv/schema.sql\"\n")
  assert c.schema == "priv/schema.sql"
  assert c.out_dir == "src/db"
  assert c.driver == "pog"
}

pub fn parse_overrides_test() {
  let toml =
    "schema = \"db/schema.sql\"\nout_dir = \"src/gen\"\ndriver = \"pog\"\n"
  let assert Ok(c) = config.parse(toml)
  assert c.out_dir == "src/gen"
}

pub fn parse_custom_type_test() {
  let toml =
    "schema = \"s.sql\"\n[types.timestamptz]\ngleam_type = \"gleam/time/timestamp.Timestamp\"\ndecoder = \"ts.decoder()\"\nencoder = \"pog.text(ts.to_rfc3339($))\"\n"
  let assert Ok(c) = config.parse(toml)
  let assert Ok(m) = dict.get(c.types, "timestamptz")
  assert m.gleam_type == "gleam/time/timestamp.Timestamp"
}

pub fn parse_rename_test() {
  let toml = "schema = \"s.sql\"\n[rename]\n\"users.type\" = \"kind\"\n"
  let assert Ok(c) = config.parse(toml)
  assert dict.get(c.renames, "users.type") == Ok("kind")
}

pub fn unknown_key_is_error_test() {
  let assert Error(error.ConfigError(_, Some("out_dir"))) =
    config.parse("schema = \"s.sql\"\nout_dr = \"src/db\"\n")
}

pub fn missing_schema_is_error_test() {
  let assert Error(error.ConfigError(_, _)) = config.parse("out_dir = \"x\"\n")
}

pub fn invalid_toml_is_error_test() {
  let assert Error(error.ConfigError(_, _)) = config.parse("schema = = =\n")
}
