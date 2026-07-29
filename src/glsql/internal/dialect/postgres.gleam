import gleam/dict.{type Dict}
import glsql/internal/mapping.{type TypeMapping, TypeMapping}

/// Postgres types that pog has no decoder for, so glsql cannot pick a Gleam
/// type on its own. Using one needs a `[types]` entry in glsql.toml. They are
/// listed so the error can say that, instead of guessing at a near-miss name.
pub const unmapped_types = [
  "int4range", "int8range", "numrange", "tsrange", "tstzrange", "daterange",
  "int4multirange", "int8multirange", "nummultirange", "tsmultirange",
  "tstzmultirange", "datemultirange", "interval", "timetz",
  "time with time zone", "money", "xml", "bit", "bit varying", "point", "line",
  "lseg", "box", "path", "polygon", "circle", "hstore", "ltree", "tsquery",
  "macaddr8",
]

pub fn builtin_types() -> Dict(String, TypeMapping) {
  dict.from_list([
    #("text", text()),
    #("varchar", text()),
    #("character varying", text()),
    #("char", text()),
    #("citext", text()),
    #("uuid", text()),
    #("int2", int()),
    #("smallint", int()),
    #("int4", int()),
    #("int", int()),
    #("integer", int()),
    #("int8", int()),
    #("bigint", int()),
    #("serial", int()),
    #("bigserial", int()),
    #("smallserial", int()),
    #("bool", bool()),
    #("boolean", bool()),
    #("float4", float()),
    #("real", float()),
    #("float8", float()),
    #("double precision", float()),
    // numeric comes back as a whole number when it has no fractional part,
    // so it needs a decoder that accepts both shapes.
    #("numeric", numeric()),
    #("decimal", numeric()),
    #("json", text()),
    #("jsonb", text()),
    #("bytea", bit_array()),
    #("tsvector", text()),
    #("inet", text()),
    #("cidr", text()),
    #("macaddr", text()),
    // pog asks the driver for microseconds, so both timestamp types decode
    // the same way.
    #("timestamp", timestamp()),
    #("timestamptz", timestamp()),
    #("timestamp with time zone", timestamp()),
    #("timestamp without time zone", timestamp()),
    #("date", date()),
    #("time", time_of_day()),
    #("time without time zone", time_of_day()),
  ])
}

fn text() -> TypeMapping {
  TypeMapping(
    gleam_type: "String",
    decoder: "decode.string",
    encoder: "pog.text($)",
    imports: [],
  )
}

fn int() -> TypeMapping {
  TypeMapping(
    gleam_type: "Int",
    decoder: "decode.int",
    encoder: "pog.int($)",
    imports: [],
  )
}

fn float() -> TypeMapping {
  TypeMapping(
    gleam_type: "Float",
    decoder: "decode.float",
    encoder: "pog.float($)",
    imports: [],
  )
}

fn bool() -> TypeMapping {
  TypeMapping(
    gleam_type: "Bool",
    decoder: "decode.bool",
    encoder: "pog.bool($)",
    imports: [],
  )
}

fn numeric() -> TypeMapping {
  TypeMapping(
    gleam_type: "Float",
    decoder: "pog.numeric_decoder()",
    encoder: "pog.float($)",
    imports: [],
  )
}

fn timestamp() -> TypeMapping {
  TypeMapping(
    gleam_type: "timestamp.Timestamp",
    decoder: "pog.timestamp_decoder()",
    encoder: "pog.timestamp($)",
    imports: ["gleam/time/timestamp"],
  )
}

fn date() -> TypeMapping {
  TypeMapping(
    gleam_type: "calendar.Date",
    decoder: "pog.calendar_date_decoder()",
    encoder: "pog.calendar_date($)",
    imports: ["gleam/time/calendar"],
  )
}

fn time_of_day() -> TypeMapping {
  TypeMapping(
    gleam_type: "calendar.TimeOfDay",
    decoder: "pog.calendar_time_of_day_decoder()",
    encoder: "pog.calendar_time_of_day($)",
    imports: ["gleam/time/calendar"],
  )
}

fn bit_array() -> TypeMapping {
  TypeMapping(
    gleam_type: "BitArray",
    decoder: "decode.bit_array",
    encoder: "pog.bytea($)",
    imports: [],
  )
}
