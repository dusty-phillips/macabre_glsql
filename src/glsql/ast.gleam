import gleam/option.{type Option}

pub type SchemaAst {
  SchemaAst(tables: List(Table))
}

pub type Table {
  Table(
    name: String,
    schema: Option(String),
    columns: List(Column),
    constraints: List(TableConstraint),
    pos: Int,
  )
}

pub type Column {
  Column(
    name: String,
    sql_type: SqlType,
    constraints: List(ColumnConstraint),
    pos: Int,
  )
}

pub type SqlType {
  SqlType(name: String, args: List(String), array_dims: Int, pos: Int)
}

pub type ColumnConstraint {
  NotNull(pos: Int)
  Nullable(pos: Int)
  PrimaryKey(pos: Int)
  Unique(pos: Int)
  Default(expr: String, pos: Int)
  References(table: String, columns: List(String), pos: Int)
  Check(expr: String, pos: Int)
}

pub type TableConstraint {
  TablePrimaryKey(columns: List(String), pos: Int)
  TableUnique(columns: List(String), pos: Int)
  TableForeignKey(
    columns: List(String),
    ref_table: String,
    ref_columns: List(String),
    pos: Int,
  )
  TableCheck(expr: String, pos: Int)
}
