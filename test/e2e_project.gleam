//// A small project the generated modules get built in.
////
//// It lives under `build/`, which the glsql project does not compile. Keeping
//// the generated code out of `test/` means a codegen mistake fails a test,
//// rather than breaking the build of the very suite meant to catch it and
//// leaving files behind that have to be deleted by hand.

import gleam/result
import glsql
import simplifile

pub const dir = "build/glsql_e2e"

/// Matches `out_dir` in the fixture config.
pub const src = "build/glsql_e2e/src"

/// The generated code imports the driver, and dates need `gleam_time`. glsql
/// is deliberately not a dependency: pointing at it by path makes this build
/// wait on the one already running the tests, so the single module the
/// generated code needs from it gets copied in instead.
const gleam_toml = "name = \"glsql_e2e\"
version = \"1.0.0\"

[dependencies]
gleam_stdlib = \">= 0.44.0 and < 2.0.0\"
pog = \">= 4.1.0 and < 5.0.0\"
gleam_time = \">= 1.8.0 and < 2.0.0\"
"

/// Set the project up and generate the fixture schema into it, starting from an
/// empty source directory so nothing from an earlier run can be mistaken for
/// output. Gives back the number of modules written.
pub fn prepare() -> Result(Int, String) {
  let _ = simplifile.delete(src)
  use _ <- result.try(
    simplifile.create_directory_all(src <> "/glsql")
    |> result.replace_error("cannot create " <> src),
  )
  use _ <- result.try(
    simplifile.write(dir <> "/gleam.toml", gleam_toml)
    |> result.replace_error("cannot write gleam.toml"),
  )
  use schema <- result.try(
    simplifile.read("src/glsql/schema.gleam")
    |> result.replace_error("cannot read src/glsql/schema.gleam"),
  )
  use _ <- result.try(
    simplifile.write(src <> "/glsql/schema.gleam", schema)
    |> result.replace_error("cannot copy schema.gleam"),
  )
  glsql.run("test/fixtures/glsql.toml")
}

/// Fetch and compile the dependencies before the tests start. A first build
/// downloads and builds the driver, which takes longer than a single test is
/// given to run, so doing it here leaves the tests with a quick rebuild.
///
/// Anything that goes wrong is left alone, because the tests that follow do the
/// same work and report properly on it.
pub fn warm_up() -> Nil {
  case prepare() {
    Ok(_) -> {
      let _ = build()
      Nil
    }
    Error(_) -> Nil
  }
}

/// Whether the project builds. 0 means it does.
pub fn build() -> Int {
  build_project(dir)
}

@external(erlang, "glsql_ffi", "build_project")
fn build_project(dir: String) -> Int

/// Whether the generated files are already formatted. 0 means they are.
@external(erlang, "glsql_ffi", "format_check")
pub fn format_check(dir: String) -> Int
