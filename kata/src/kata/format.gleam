/// kata/format — Format abstraction for pluggable serialization.
/// Unifies decode/encode across different wire formats (JSON, form data, etc.).
import gleam/result
import kata/error.{type Error}
import kata/schema as kata_schema
import kata/value.{type Value}

/// Describes the parsing behavior of a format.
pub type ParseMode {
  /// Types must match exactly (e.g. JSON has native int/bool).
  Strict
  /// Values may be coerced from strings (e.g. form data, env vars).
  Coerce
}

/// A pluggable wire format that converts between raw representation and Value.
pub type Format(raw) {
  Format(
    name: String,
    parse: fn(raw) -> Result(Value, String),
    serialize: fn(Value) -> Result(raw, String),
    mode: ParseMode,
  )
}

/// Unified error for format-aware decoding.
pub type DecodeError {
  /// The raw input could not be parsed into a Value.
  ParseError(message: String)
  /// The Value did not match the schema.
  SchemaError(errors: List(Error))
}

/// Decode raw input through a format and schema in one step.
pub fn decode(
  s: kata_schema.Schema(a),
  format: Format(raw),
  input: raw,
) -> Result(a, DecodeError) {
  use value <- result.try(
    format.parse(input) |> result.map_error(ParseError),
  )
  kata_schema.decode(s, value) |> result.map_error(SchemaError)
}

/// Encode a typed value to raw output through a schema and format.
pub fn encode(
  s: kata_schema.Schema(a),
  format: Format(raw),
  value: a,
) -> Result(raw, String) {
  let v = kata_schema.encode(s, value)
  format.serialize(v)
}
