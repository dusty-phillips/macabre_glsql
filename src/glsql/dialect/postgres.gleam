import gleam/dict.{type Dict}
import glsql/mapping.{type TypeMapping, TypeMapping}

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
    #("numeric", float()),
    #("decimal", float()),
    #("json", text()),
    #("jsonb", text()),
    #("bytea", bit_array()),
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

fn bit_array() -> TypeMapping {
  TypeMapping(
    gleam_type: "BitArray",
    decoder: "decode.bit_array",
    encoder: "pog.bytea($)",
    imports: [],
  )
}
