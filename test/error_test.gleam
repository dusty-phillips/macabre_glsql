import gleam/option.{None, Some}
import gleam/string
import glsql/error

const source = "create table t (\n  a text\n);\n"

pub fn render_includes_position_test() {
  let out =
    error.render(error.ParseError("Bad thing", 19, None), "schema.sql", source)
  assert string.contains(out, "schema.sql:2:3")
}

pub fn render_includes_source_line_test() {
  let out =
    error.render(error.ParseError("Bad thing", 19, None), "schema.sql", source)
  assert string.contains(out, "a text")
}

pub fn render_includes_caret_test() {
  let out =
    error.render(error.ParseError("Bad thing", 19, None), "schema.sql", source)
  assert string.contains(out, "^")
}

pub fn render_includes_hint_test() {
  let out =
    error.render(
      error.UnknownStatement("craete", 0, Some("create")),
      "schema.sql",
      source,
    )
  assert string.contains(out, "did you mean `create`")
}

pub fn render_omits_hint_when_absent_test() {
  let out =
    error.render(error.ParseError("Bad thing", 0, None), "schema.sql", source)
  assert !string.contains(out, "did you mean")
}

pub fn render_config_error_test() {
  let out = error.render(error.ConfigError("Bad key", None), "glsql.toml", "")
  assert string.contains(out, "Bad key")
}
