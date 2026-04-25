/// kata_form — Form data adapter for kata.
/// Parses application/x-www-form-urlencoded into kata Value and decodes with schemas.
///
/// Form data is string-based, so use `kata/coerce` for int/float/bool fields:
///
/// ```gleam
/// import kata
/// import kata/coerce
/// import kata_form
///
/// fn login_schema() {
///   use email <- kata.field("email", kata.string(), fn(l: Login) { l.email })
///   use remember <- kata.field("remember", coerce.bool(), fn(l: Login) { l.remember })
///   kata.done(Login(email:, remember:))
/// }
///
/// let assert Ok(login) = kata_form.decode(login_schema(), "email=a%40b.com&remember=true")
/// ```
import gleam/float
import gleam/int
import gleam/list
import gleam/uri
import kata/error.{type Error}
import kata/format.{type Format, Coerce, Format}
import kata/schema.{type Schema}
import kata/value.{
  type Value, VBool, VFloat, VInt, VList, VNull, VObject, VString,
}

pub type FormError {
  /// Failed to parse URL-encoded form body
  ParseError(message: String)
  /// Schema validation failed
  SchemaError(errors: List(Error))
}

/// Form format for use with kata/format.decode and kata/format.encode.
pub fn format() -> Format(String) {
  Format(name: "form", parse: parse, serialize: serialize, mode: Coerce)
}

/// Serialize a Value to a URL-encoded form string.
/// Only VObject with string-representable values is supported.
pub fn serialize(v: Value) -> Result(String, String) {
  case v {
    VObject(entries) -> {
      let result =
        list.try_map(entries, fn(pair) {
          case value_to_string(pair.1) {
            Ok(s) -> Ok(#(pair.0, s))
            Error(e) -> Error(e)
          }
        })
      case result {
        Ok(pairs) -> Ok(uri.query_to_string(pairs))
        Error(e) -> Error(e)
      }
    }
    _ -> Error("form format can only serialize VObject")
  }
}

fn value_to_string(v: Value) -> Result(String, String) {
  case v {
    VString(s) -> Ok(s)
    VInt(n) -> Ok(int.to_string(n))
    VFloat(f) -> Ok(float.to_string(f))
    VBool(True) -> Ok("true")
    VBool(False) -> Ok("false")
    VNull -> Ok("")
    VList(_) -> Error("form format cannot serialize lists")
    VObject(_) -> Error("form format cannot serialize nested objects")
  }
}

/// Parse a URL-encoded form body into a kata Value.
/// Returns VObject with all values as VString.
pub fn parse(body: String) -> Result(Value, String) {
  case uri.parse_query(body) {
    Ok(pairs) -> Ok(pairs_to_value(pairs))
    Error(_) -> Error("invalid URL-encoded form data: " <> body)
  }
}

/// Decode a URL-encoded form body using a schema.
/// Use `kata/coerce` schemas for non-string fields.
pub fn decode(schema: Schema(a), body: String) -> Result(a, FormError) {
  case parse(body) {
    Ok(value) ->
      case schema.decode(schema, value) {
        Ok(a) -> Ok(a)
        Error(errs) -> Error(SchemaError(errs))
      }
    Error(msg) -> Error(ParseError(msg))
  }
}

/// Decode from pre-parsed key-value pairs (e.g. from wisp's FormData.values).
pub fn decode_pairs(
  schema: Schema(a),
  pairs: List(#(String, String)),
) -> Result(a, FormError) {
  case schema.decode(schema, pairs_to_value(pairs)) {
    Ok(a) -> Ok(a)
    Error(errs) -> Error(SchemaError(errs))
  }
}

/// Convert key-value pairs to a kata Value.
fn pairs_to_value(pairs: List(#(String, String))) -> Value {
  VObject(list.map(pairs, fn(pair) { #(pair.0, VString(pair.1)) }))
}
