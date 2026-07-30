import e2e_project
import gleam/string
import simplifile

pub fn generates_fixture_modules_test() {
  let assert Ok(3) = e2e_project.prepare()

  let assert Ok(users) = simplifile.read(e2e_project.src <> "/users.gleam")
  assert string.contains(users, "pub type Users {")
  assert string.contains(users, "tags: List(String)")
  assert string.contains(users, "display_name: Option(String)")

  let assert Ok(posts) = simplifile.read(e2e_project.src <> "/posts.gleam")
  assert string.contains(posts, "author_id: String")
}

/// The whole point of the generator: what it writes has to compile. This also
/// covers a type mapping that names a module, since the fixture maps
/// `timestamptz` to `timestamp.Timestamp` and the build fails without the
/// matching import.
pub fn generated_code_compiles_test() {
  let assert Ok(_) = e2e_project.prepare()
  assert e2e_project.build() == 0
}

/// Generated files are written already formatted, so a project that runs
/// `gleam format --check` over its own source stays green. codegen decides
/// where to wrap by counting characters, so this catches it drifting from what
/// the formatter actually does.
pub fn generated_code_is_already_formatted_test() {
  let assert Ok(_) = e2e_project.prepare()
  assert e2e_project.format_check(e2e_project.src) == 0
}
