import gleam/io
import gleam/list
import gleam/result
import gleam/string
import glsql/internal/codegen
import glsql/internal/config
import glsql/internal/error
import glsql/internal/lexer
import glsql/internal/parser
import glsql/internal/resolve
import glsql/internal/validate
import simplifile

pub fn main() -> Nil {
  case run("glsql.toml") {
    Ok(count) ->
      io.println("Generated " <> string.inspect(count) <> " modules.")
    Error(message) -> {
      io.println_error(message)
      halt(1)
    }
  }
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

pub fn run(config_path: String) -> Result(Int, String) {
  use cfg <- result.try(
    config.load(config_path)
    |> result.map_error(error.render(_, config_path, "")),
  )

  use source <- result.try(
    simplifile.read(cfg.schema)
    |> result.map_error(fn(e) {
      "error: could not read " <> cfg.schema <> " (" <> string.inspect(e) <> ")"
    }),
  )

  use tokens <- result.try(
    lexer.lex(source)
    |> result.map_error(error.render(_, cfg.schema, source)),
  )

  use schema <- result.try(
    parser.parse(tokens)
    |> result.map_error(error.render(_, cfg.schema, source)),
  )

  use _ <- result.try(
    validate.check(schema, cfg)
    |> result.map_error(render_all(_, cfg.schema, source)),
  )

  use resolved <- result.try(
    resolve.resolve(schema, cfg)
    |> result.map_error(render_all(_, cfg.schema, source)),
  )

  let schema_import = module_prefix(cfg.out_dir) <> codegen.schema_module

  // Generate everything in memory first, so a failure never leaves a
  // half-written out_dir.
  let files =
    list.map(resolved.tables, fn(table) {
      #(
        cfg.out_dir <> "/" <> table.module_name <> ".gleam",
        codegen.generate_table(table, cfg.driver, cfg.schema, schema_import),
      )
    })

  let files = [
    #(
      cfg.out_dir <> "/" <> codegen.schema_module <> ".gleam",
      codegen.generate_schema_module(cfg.schema),
    ),
    ..files
  ]

  use _ <- result.try(
    simplifile.create_directory_all(cfg.out_dir)
    |> result.map_error(fn(e) {
      "error: could not create "
      <> cfg.out_dir
      <> " ("
      <> string.inspect(e)
      <> ")"
    }),
  )

  use _ <- result.try(
    list.try_each(files, fn(file) {
      let #(path, contents) = file
      simplifile.write(path, contents)
      |> result.map_error(fn(e) {
        "error: could not write " <> path <> " (" <> string.inspect(e) <> ")"
      })
    }),
  )

  // The count is of tables, since the shared `Column` module is not one.
  Ok(list.length(resolved.tables))
}

/// What the generated modules have to put in front of each other's names to
/// import them. Gleam names a module by its path under `src` or `test`, so that
/// leading directory is not part of it.
fn module_prefix(out_dir: String) -> String {
  let inner = case string.split_once(out_dir, "/") {
    Ok(#("src", rest)) | Ok(#("test", rest)) | Ok(#("dev", rest)) -> rest
    _ ->
      case out_dir {
        "src" | "test" | "dev" -> ""
        _ -> out_dir
      }
  }
  case inner {
    "" -> ""
    _ -> inner <> "/"
  }
}

fn render_all(
  errors: List(error.Error),
  filename: String,
  source: String,
) -> String {
  errors
  |> list.map(error.render(_, filename, source))
  |> string.join("\n")
}
