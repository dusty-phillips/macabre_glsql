import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import glsql/error.{type Error, ConfigError}
import glsql/mapping.{type TypeMapping, TypeMapping}
import glsql/suggest
import simplifile
import tom

pub type TableNaming {
  TableNaming(module: Option(String), type_name: Option(String))
}

pub type Config {
  Config(
    schema: String,
    out_dir: String,
    driver: String,
    types: Dict(String, TypeMapping),
    renames: Dict(String, String),
    table_names: Dict(String, TableNaming),
  )
}

const known_keys = ["schema", "out_dir", "driver", "types", "rename", "tables"]

const known_type_keys = ["gleam_type", "decoder", "encoder", "imports"]

pub fn default() -> Config {
  Config(
    schema: "priv/schema.sql",
    out_dir: "src/db",
    driver: "pog",
    types: dict.new(),
    renames: dict.new(),
    table_names: dict.new(),
  )
}

pub fn parse(src: String) -> Result(Config, Error) {
  use parsed <- result.try(
    tom.parse(src)
    |> result.map_error(fn(_) {
      ConfigError("This file is not valid TOML", None)
    }),
  )

  use _ <- result.try(check_keys(dict.keys(parsed), known_keys))

  use schema <- result.try(require_string(parsed, "schema"))
  let out_dir = optional_string(parsed, "out_dir", "src/db")
  let driver = optional_string(parsed, "driver", "pog")
  use types <- result.try(parse_types(parsed))
  let renames = parse_renames(parsed)
  let table_names = parse_table_names(parsed)

  Ok(Config(
    schema: schema,
    out_dir: out_dir,
    driver: driver,
    types: types,
    renames: renames,
    table_names: table_names,
  ))
}

fn check_keys(found: List(String), known: List(String)) -> Result(Nil, Error) {
  case list.find(found, fn(k) { !list.contains(known, k) }) {
    Error(Nil) -> Ok(Nil)
    Ok(bad) ->
      Error(ConfigError(
        "`" <> bad <> "` is not a glsql.toml key",
        suggest.closest(bad, known),
      ))
  }
}

fn require_string(
  parsed: Dict(String, tom.Toml),
  key: String,
) -> Result(String, Error) {
  case tom.get_string(parsed, [key]) {
    Ok(v) -> Ok(v)
    Error(_) -> Error(ConfigError("glsql.toml must set `" <> key <> "`", None))
  }
}

fn optional_string(
  parsed: Dict(String, tom.Toml),
  key: String,
  fallback: String,
) -> String {
  case tom.get_string(parsed, [key]) {
    Ok(v) -> v
    Error(_) -> fallback
  }
}

fn parse_types(
  parsed: Dict(String, tom.Toml),
) -> Result(Dict(String, TypeMapping), Error) {
  case tom.get_table(parsed, ["types"]) {
    Error(_) -> Ok(dict.new())
    Ok(types) ->
      types
      |> dict.to_list
      |> list.try_map(fn(pair) {
        let #(name, _) = pair
        use _ <- result.try(check_type_keys(parsed, name))
        use gleam_type <- result.try(type_field(parsed, name, "gleam_type"))
        use decoder <- result.try(type_field(parsed, name, "decoder"))
        use encoder <- result.try(type_field(parsed, name, "encoder"))
        Ok(#(
          string.lowercase(name),
          TypeMapping(
            gleam_type: gleam_type,
            decoder: decoder,
            encoder: encoder,
            imports: [],
          ),
        ))
      })
      |> result.map(dict.from_list)
  }
}

fn check_type_keys(
  parsed: Dict(String, tom.Toml),
  name: String,
) -> Result(Nil, Error) {
  case tom.get_table(parsed, ["types", name]) {
    Error(_) -> Ok(Nil)
    Ok(t) -> check_keys(dict.keys(t), known_type_keys)
  }
}

fn type_field(
  parsed: Dict(String, tom.Toml),
  name: String,
  field: String,
) -> Result(String, Error) {
  case tom.get_string(parsed, ["types", name, field]) {
    Ok(v) -> Ok(v)
    Error(_) ->
      Error(ConfigError(
        "[types." <> name <> "] must set `" <> field <> "`",
        None,
      ))
  }
}

fn parse_renames(parsed: Dict(String, tom.Toml)) -> Dict(String, String) {
  case tom.get_table(parsed, ["rename"]) {
    Error(_) -> dict.new()
    Ok(t) ->
      t
      |> dict.to_list
      |> list.filter_map(fn(pair) {
        let #(k, _) = pair
        case tom.get_string(parsed, ["rename", k]) {
          Ok(v) -> Ok(#(k, v))
          Error(_) -> Error(Nil)
        }
      })
      |> dict.from_list
  }
}

fn parse_table_names(
  parsed: Dict(String, tom.Toml),
) -> Dict(String, TableNaming) {
  case tom.get_table(parsed, ["tables"]) {
    Error(_) -> dict.new()
    Ok(t) ->
      t
      |> dict.to_list
      |> list.map(fn(pair) {
        let #(name, _) = pair
        let module = case tom.get_string(parsed, ["tables", name, "module"]) {
          Ok(v) -> Some(v)
          Error(_) -> None
        }
        let type_name = case tom.get_string(parsed, ["tables", name, "type"]) {
          Ok(v) -> Some(v)
          Error(_) -> None
        }
        #(name, TableNaming(module: module, type_name: type_name))
      })
      |> dict.from_list
  }
}

pub fn load(path: String) -> Result(Config, Error) {
  case simplifile.read(path) {
    Ok(src) -> parse(src)
    Error(_) -> Ok(default())
  }
}
