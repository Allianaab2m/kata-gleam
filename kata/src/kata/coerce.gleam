/// Coercing schema primitives for string-based formats (form data, env vars).
/// These accept both the native Value type and VString representations.
///
/// Use these instead of kata.int()/float()/bool() when the input format
/// is string-based (e.g. URL-encoded forms, environment variables).
///
/// ```gleam
/// import kata
/// import kata/coerce
///
/// fn form_schema() {
///   use name <- kata.field("name", kata.string(), fn(u: User) { u.name })
///   use age <- kata.field("age", coerce.int(), fn(u: User) { u.age })
///   kata.done(User(name:, age:))
/// }
/// ```
import kata/schema.{type Schema}

/// Int that also accepts VString("42") -> 42
pub fn int() -> Schema(Int) {
  schema.coerce_int()
}

/// Float that also accepts VString("3.14") -> 3.14 and VInt(1) -> 1.0
pub fn float() -> Schema(Float) {
  schema.coerce_float()
}

/// Bool that also accepts VString("true"/"false")
pub fn bool() -> Schema(Bool) {
  schema.coerce_bool()
}
