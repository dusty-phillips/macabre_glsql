import gleam/dict
import gleam/option.{Some}
import glsql/internal/config
import glsql/internal/error

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
  // `gleam_type` is written into the generated code as it stands, so it has to
  // be a name a Gleam file can use, qualified by the module's last segment.
  let toml =
    "schema = \"s.sql\"\n[types.timestamptz]\ngleam_type = \"timestamp.Timestamp\"\ndecoder = \"pog.timestamp_decoder()\"\nencoder = \"pog.timestamp($)\"\n"
  let assert Ok(c) = config.parse(toml)
  let assert Ok(m) = dict.get(c.types, "timestamptz")
  assert m.gleam_type == "timestamp.Timestamp"
  assert m.imports == []
}

pub fn parse_custom_type_imports_test() {
  let toml =
    "schema = \"s.sql\"\n[types.citext]\ngleam_type = \"custom.Text\"\ndecoder = \"custom.decoder()\"\nencoder = \"pog.text(custom.to_string($))\"\nimports = [\"my_app/custom\"]\n"
  let assert Ok(c) = config.parse(toml)
  let assert Ok(m) = dict.get(c.types, "citext")
  assert m.imports == ["my_app/custom"]
}

pub fn non_string_import_is_error_test() {
  let toml =
    "schema = \"s.sql\"\n[types.citext]\ngleam_type = \"String\"\ndecoder = \"decode.string\"\nencoder = \"pog.text($)\"\nimports = [1]\n"
  let assert Error(error.ConfigError(_, _)) = config.parse(toml)
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
