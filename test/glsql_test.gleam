import e2e_project
import gleeunit

pub fn main() -> Nil {
  // Done here rather than inside the test, because a first run has to fetch and
  // build the driver, which takes longer than one test is given.
  e2e_project.warm_up()
  gleeunit.main()
}
