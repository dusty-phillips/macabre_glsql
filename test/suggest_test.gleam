import gleam/option.{None, Some}
import glsql/suggest

const keywords = ["create", "table", "alter", "index"]

pub fn closest_finds_typo_test() {
  assert suggest.closest("craete", keywords) == Some("create")
}

pub fn closest_is_case_insensitive_test() {
  assert suggest.closest("CRAETE", keywords) == Some("create")
}

pub fn closest_rejects_distant_words_test() {
  assert suggest.closest("elephant", keywords) == None
}

pub fn closest_handles_empty_candidates_test() {
  assert suggest.closest("create", []) == None
}

pub fn closest_exact_match_test() {
  assert suggest.closest("table", keywords) == Some("table")
}
