import gleam/string
import glsql
import simplifile

pub fn generates_fixture_modules_test() {
  let _ = simplifile.delete("test/fixtures/generated")
  let assert Ok(count) = glsql.run("test/fixtures/glsql.toml")
  assert count == 2

  let assert Ok(users) = simplifile.read("test/fixtures/generated/users.gleam")
  assert string.contains(users, "pub type Users {")
  assert string.contains(users, "tags: List(String)")
  assert string.contains(users, "display_name: Option(String)")

  let assert Ok(posts) = simplifile.read("test/fixtures/generated/posts.gleam")
  assert string.contains(posts, "author_id: String")
}

pub fn generated_code_compiles_test() {
  // pog is a real project dependency, so the generated modules can be
  // type-checked as-is, in place under test/fixtures/generated.
  let assert Ok(_) = glsql.run("test/fixtures/glsql.toml")
  let result = check_project()
  assert result == 0
}

@external(erlang, "glsql_ffi", "check_project")
fn check_project() -> Int
