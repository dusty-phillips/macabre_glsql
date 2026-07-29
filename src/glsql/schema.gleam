/// A column descriptor. The `value` type parameter is phantom: it records the
/// Gleam type of the column so query builders can be type-safe.
pub type Column(value) {
  Column(
    table: String,
    name: String,
    sql_type: String,
    nullable: Bool,
    primary_key: Bool,
  )
}
