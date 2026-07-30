import generated/glsql_schema.{Column}
import gleam/dynamic
import gleam/dynamic/decode

pub type UserPreview {
  UserPreview(id: String, email: String)
}

pub fn column_decoder_composes_into_a_subset_test() {
  let col_id = Column("users", "id", "uuid", False, True, decode.string)
  let col_email = Column("users", "email", "text", False, False, decode.string)

  let decoder = {
    use id <- decode.field(0, col_id.decoder)
    use email <- decode.field(1, col_email.decoder)
    decode.success(UserPreview(id:, email:))
  }

  let row =
    dynamic.list([dynamic.string("u1"), dynamic.string("ada@example.com")])

  let assert Ok(preview) = decode.run(row, decoder)
  assert preview == UserPreview(id: "u1", email: "ada@example.com")
}
