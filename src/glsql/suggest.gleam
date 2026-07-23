import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/string

pub fn closest(word: String, candidates: List(String)) -> Option(String) {
  let needle = string.lowercase(word)
  let limit = int.min(2, string.length(needle) - 1)

  candidates
  |> list.map(fn(c) { #(c, distance(needle, string.lowercase(c))) })
  |> list.filter(fn(pair) { pair.1 <= limit })
  |> list.sort(fn(a, b) { int.compare(a.1, b.1) })
  |> list.first
  |> option.from_result
  |> option.map(fn(pair) { pair.0 })
}

pub fn distance(a: String, b: String) -> Int {
  let a = string.to_graphemes(a)
  let b = string.to_graphemes(b)
  let first_row =
    int.range(from: 0, to: list.length(b) + 1, with: [], run: fn(acc, i) {
      [i, ..acc]
    })
    |> list.reverse
  let final =
    list.index_fold(a, first_row, fn(prev, ac, i) { step_row(b, prev, ac, i) })
  case list.last(final) {
    Ok(d) -> d
    Error(Nil) -> 0
  }
}

fn step_row(
  b: List(String),
  prev: List(Int),
  ac: String,
  i: Int,
) -> List(Int) {
  let start = i + 1
  let #(row, _) =
    list.fold(b, #([start], prev), fn(state, bc) {
      let #(acc, prev_rest) = state
      case acc, prev_rest {
        [left, ..], [diag, up, ..rest] -> {
          let cost = case ac == bc {
            True -> 0
            False -> 1
          }
          let best =
            int.min(int.min(left + 1, up + 1), diag + cost)
          #([best, ..acc], [up, ..rest])
        }
        _, _ -> state
      }
    })
  list.reverse(row)
}
