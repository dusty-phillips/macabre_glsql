# glsql

[![Package Version](https://img.shields.io/hexpm/v/glsql)](https://hex.pm/packages/glsql)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glsql/)

```sh
gleam add glsql@1
```

## Usage

Write your schema in a plain `.sql` file, then configure glsql:

```toml
# glsql.toml
schema = "priv/schema.sql"
out_dir = "src/db"
driver = "pog"
```

Generate:

```sh
gleam run -m glsql
```

glsql never connects to a database. It reads your schema file and nothing else,
so generation works offline and in CI.

Further documentation can be found at <https://hexdocs.pm/glsql>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
