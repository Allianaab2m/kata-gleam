/// kata_json — JSON adapter for kata.
/// Provides parse/serialize (schema-independent) and decode/encode (schema-aware).
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import kata/error.{type Error}
import kata/format.{type Format, Format, Strict}
import kata/schema
import kata/value.{
  type Value, VBool, VFloat, VInt, VList, VNull, VObject, VString,
}

pub type JsonError {
  /// JSON parse error
  ParseError(message: String)
  /// Schema validation error
  SchemaError(errors: List(Error))
}

/// JSON format for use with kata/format.decode and kata/format.encode.
pub fn format() -> Format(String) {
  Format(
    name: "json",
    parse: parse,
    serialize: fn(v) { Ok(serialize(v)) },
    mode: Strict,
  )
}

/// Parse a JSON string into a Value (schema-independent).
pub fn parse(input: String) -> Result(Value, String) {
  case json.parse(input, value_decoder()) {
    Ok(v) -> Ok(v)
    Error(e) -> Error(json_error_to_string(e))
  }
}

/// Serialize a Value to a JSON string (schema-independent).
pub fn serialize(v: Value) -> String {
  value_to_json(v)
  |> json.to_string()
}

/// Decode a JSON string using a schema.
pub fn decode_json(
  schema: schema.Schema(a),
  input: String,
) -> Result(a, JsonError) {
  case parse(input) {
    Ok(v) ->
      case schema.decode(schema, v) {
        Ok(a) -> Ok(a)
        Error(errs) -> Error(SchemaError(errs))
      }
    Error(msg) -> Error(ParseError(msg))
  }
}

/// Encode a value to a JSON string using a schema.
pub fn encode_json(schema: schema.Schema(a), value: a) -> String {
  let v = schema.encode(schema, value)
  serialize(v)
}

// --- Internal: Value decoder ---

fn value_decoder() -> decode.Decoder(Value) {
  decode.one_of(decode.bool |> decode.map(VBool), [
    decode.int |> decode.map(VInt),
    decode.float |> decode.map(VFloat),
    decode.string |> decode.map(VString),
    decode.list(decode.recursive(fn() { value_decoder() }))
      |> decode.map(VList),
    decode.dict(decode.string, decode.recursive(fn() { value_decoder() }))
      |> decode.map(fn(d) { VObject(dict.to_list(d)) }),
    null_decoder(),
  ])
}

fn null_decoder() -> decode.Decoder(Value) {
  decode.optional(decode.string)
  |> decode.then(fn(opt) {
    case opt {
      None -> decode.success(VNull)
      Some(_) -> decode.failure(VNull, expected: "null")
    }
  })
}

// --- Internal: Value to Json ---

fn value_to_json(v: Value) -> json.Json {
  case v {
    VNull -> json.null()
    VBool(b) -> json.bool(b)
    VInt(n) -> json.int(n)
    VFloat(f) -> json.float(f)
    VString(s) -> json.string(s)
    VList(items) -> json.preprocessed_array(list.map(items, value_to_json))
    VObject(entries) ->
      json.object(
        list.map(entries, fn(pair) { #(pair.0, value_to_json(pair.1)) }),
      )
  }
}

fn json_error_to_string(e: json.DecodeError) -> String {
  case e {
    json.UnexpectedEndOfInput -> "unexpected end of input"
    json.UnexpectedByte(b) -> "unexpected byte: " <> b
    json.UnexpectedSequence(s) -> "unexpected sequence: " <> s
    json.UnableToDecode(_) -> "unable to decode"
  }
}
