import gleam/dynamic/decode

/// A column descriptor. The `value` type parameter records the Gleam type
/// of the column, and `decoder` decodes just that column, so a query that
/// selects fewer than all of a table's columns can still be decoded type
/// safely by composing the pieces it needs.
pub type Column(value) {
  Column(
    table: String,
    name: String,
    sql_type: String,
    nullable: Bool,
    primary_key: Bool,
    decoder: decode.Decoder(value),
  )
}
