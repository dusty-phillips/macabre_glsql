//// The modules under `test/generated` are committed, so the ordinary build
//// type-checks them and `gleam format --check` covers them. What is left to
//// check is that codegen still produces exactly those bytes.
////
//// Generation happens in memory here and nothing is written. A codegen mistake
//// then fails this test without putting code that does not compile into the
//// tree, which would break the next build before the tests could run.
////
//// Refresh the committed modules with `gleam run -m glsql`.

import gleam/list
import gleam/string
import glsql/internal/codegen
import glsql/internal/config
import glsql/internal/lexer
import glsql/internal/parser
import glsql/internal/resolve
import simplifile

const out_dir = "test/generated"

/// What the generated modules import each other by, matching `out_dir`.
const schema_import = "generated/" <> codegen.schema_module

fn generated() -> List(#(String, String)) {
  let assert Ok(cfg) = config.load("glsql.toml")
  let assert Ok(source) = simplifile.read(cfg.schema)
  let assert Ok(tokens) = lexer.lex(source)
  let assert Ok(schema) = parser.parse(tokens)
  let assert Ok(resolved) = resolve.resolve(schema, cfg)

  let tables =
    list.map(resolved.tables, fn(table) {
      #(
        table.module_name <> ".gleam",
        codegen.generate_table(table, cfg.driver, cfg.schema, schema_import),
      )
    })

  [
    #(
      codegen.schema_module <> ".gleam",
      codegen.generate_schema_module(cfg.schema),
    ),
    ..tables
  ]
}

pub fn committed_modules_match_codegen_test() {
  let files = generated()
  assert list.length(files) == 4

  list.each(files, fn(file) {
    let #(name, contents) = file
    let assert Ok(committed) = simplifile.read(out_dir <> "/" <> name)
    assert committed == contents
  })
}

/// Nothing is generated that is not checked in, which would leave the build
/// type-checking less than codegen writes.
pub fn no_committed_module_is_stale_test() {
  let assert Ok(on_disk) = simplifile.get_files(out_dir)
  let expected =
    generated()
    |> list.map(fn(file) { out_dir <> "/" <> file.0 })
    |> list.sort(string.compare)

  assert list.sort(on_disk, string.compare) == expected
}
