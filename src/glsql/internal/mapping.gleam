pub type TypeMapping {
  TypeMapping(
    gleam_type: String,
    decoder: String,
    encoder: String,
    imports: List(String),
  )
}
