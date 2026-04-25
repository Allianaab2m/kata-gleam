/// kata_env — Environment variable adapter for kata.
/// Reads env vars and decodes with kata schemas.
///
/// All env values are strings, so use `kata/coerce` for int/float/bool:
///
/// ```gleam
/// import kata
/// import kata/coerce
/// import kata_env
///
/// pub type Config {
///   Config(port: Int, host: String, debug: Bool)
/// }
///
/// fn config_schema() {
///   use port <- kata.field("PORT", coerce.int(), fn(c: Config) { c.port })
///   use host <- kata.field("HOST", kata.string(), fn(c: Config) { c.host })
///   use debug <- kata.optional_field("DEBUG", coerce.bool(), False, fn(c: Config) { c.debug })
///   kata.done(Config(port:, host:, debug:))
/// }
///
/// let assert Ok(config) = kata_env.decode(config_schema())
/// ```
import envoy
import gleam/dict
import gleam/list
import kata/error.{type Error}
import kata/schema.{type Schema}
import kata/value.{VObject, VString}

pub type EnvError {
  /// Schema validation failed (missing or invalid env vars)
  SchemaError(errors: List(Error))
}

/// Read all environment variables and decode using a schema.
/// Field keys in the schema correspond to env var names.
pub fn decode(schema: Schema(a)) -> Result(a, EnvError) {
  let value = env_to_value(envoy.all())
  case schema.decode(schema, value) {
    Ok(a) -> Ok(a)
    Error(errs) -> Error(SchemaError(errs))
  }
}

/// Decode from a specific set of env var names.
/// Only reads the specified keys from the environment.
pub fn decode_keys(schema: Schema(a), keys: List(String)) -> Result(a, EnvError) {
  let pairs =
    list.filter_map(keys, fn(key) {
      case envoy.get(key) {
        Ok(val) -> Ok(#(key, VString(val)))
        Error(_) -> Error(Nil)
      }
    })
  case schema.decode(schema, VObject(pairs)) {
    Ok(a) -> Ok(a)
    Error(errs) -> Error(SchemaError(errs))
  }
}

fn env_to_value(env: dict.Dict(String, String)) -> value.Value {
  VObject(
    dict.to_list(env)
    |> list.map(fn(pair) { #(pair.0, VString(pair.1)) }),
  )
}
