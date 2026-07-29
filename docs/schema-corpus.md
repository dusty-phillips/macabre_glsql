# Real schema corpus

Four public Postgres dumps to run glsql over. Worth doing after any change to
the parser or to codegen, because they turn up things a hand written fixture
never will.

They are not committed. `test/corpus/` is gitignored, so fetching them again is
the way to get them back.

## Fetch

```sh
mkdir -p test/corpus && cd test/corpus
curl -fsSL -o pagila.sql   https://raw.githubusercontent.com/devrimgunduz/pagila/master/pagila-schema.sql
curl -fsSL -o northwind.sql https://raw.githubusercontent.com/pthom/northwind_psql/master/northwind.sql
curl -fsSL -o chinook.sql  https://raw.githubusercontent.com/lerocha/chinook-database/master/ChinookDatabase/DataSources/Chinook_PostgreSql.sql
curl -fsSL -o gitlab.sql   https://raw.githubusercontent.com/gitlabhq/gitlabhq/master/db/structure.sql
```

Sizes as of July 2026: pagila 88KB, northwind 350KB, chinook 600KB, gitlab
2.9MB and 61k lines. Table counts once generated: 70, 14, 11, 1421.

## Config each one needs

northwind and chinook need nothing. pagila defines a domain and an enum of its
own:

```toml
[types]
year = { gleam_type = "Int", decoder = "decode.int", encoder = "pog.int($)" }
mpaa_rating = { gleam_type = "String", decoder = "decode.string", encoder = "pog.text($)" }
```

gitlab has a `type` column in 17 tables, and two range types:

```toml
[rename]
type = "type_"

[types]
daterange = { gleam_type = "String", decoder = "decode.string", encoder = "pog.text($)" }
int8range = { gleam_type = "String", decoder = "decode.string", encoder = "pog.text($)" }
```

## Checking the output is formatted

codegen decides where to wrap by counting characters, so it can drift from what
the formatter does. Generate, copy, format the copy, and diff:

```sh
cp -r out out_fmt
gleam format out_fmt
diff -rq out out_fmt | wc -l
```

Run this over gitlab, not over a handful of small tables. A five table probe
said the output was clean when 281 of gitlab's 1421 files still differed. The
wide tables and the long column names are where the wrapping rules show up.

## Checking the output compiles

Point a throwaway project at the generated modules, with `glsql` as a path
dependency and `pog` plus `gleam_time` as normal ones, then `gleam build`. This
catches a type mapping that names a Gleam type the project cannot see.

Leave gitlab's `application_settings` out of that project, or the build dies
with a segmentation fault. It has 582 columns, which is past the limit in the
Known limits section of the README.
