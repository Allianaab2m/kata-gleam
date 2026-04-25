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
import gleam/list
import gleam/uri
import kata/error.{type Error}
import kata/schema.{type Schema}
import kata/value.{type Value, VObject, VString}

pub type FormError {
  /// Failed to parse URL-encoded form body
  ParseError(message: String)
  /// Schema validation failed
  SchemaError(errors: List(Error))
}

/// Parse a URL-encoded form body into a kata Value.
/// Returns VObject with all values as VString.
pub fn parse(body: String) -> Result(Value, String) {
  case uri.parse_query(body) {
    Ok(pairs) -> Ok(pairs_to_value(pairs))
    Error(_) -> Error("invalid URL-encoded form data")
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
) -> Result(a, List(Error)) {
  schema.decode(schema, pairs_to_value(pairs))
}

/// Convert key-value pairs to a kata Value.
fn pairs_to_value(pairs: List(#(String, String))) -> Value {
  VObject(list.map(pairs, fn(pair) { #(pair.0, VString(pair.1)) }))
}
