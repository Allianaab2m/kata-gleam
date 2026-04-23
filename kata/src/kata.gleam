/// kata — A bidirectional schema library for Gleam.
/// Define your data shape once, decode and encode with the same definition.
import gleam/dict
import gleam/option.{type Option}
import kata/ast
import kata/error
import kata/schema
import kata/value

// --- Type re-exports ---

pub type Schema(a) =
  schema.Schema(a)

pub type Value =
  value.Value

pub type Ast =
  ast.Ast

pub type Error =
  error.Error

// --- Primitives ---

pub fn string() -> Schema(String) {
  schema.string()
}

pub fn int() -> Schema(Int) {
  schema.int()
}

pub fn float() -> Schema(Float) {
  schema.float()
}

pub fn bool() -> Schema(Bool) {
  schema.bool()
}

// --- Containers ---

pub fn list(item: Schema(a)) -> Schema(List(a)) {
  schema.list(item)
}

pub fn optional(inner: Schema(a)) -> Schema(Option(a)) {
  schema.optional(inner)
}

pub fn dict(
  key_schema: Schema(k),
  val_schema: Schema(v),
) -> Schema(dict.Dict(k, v)) {
  schema.dict(key_schema, val_schema)
}

// --- Record Builder ---

pub fn field(
  key: String,
  field_schema: Schema(a),
  get: fn(final) -> a,
  next: fn(a) -> Schema(final),
) -> Schema(final) {
  schema.field(key, field_schema, get, next)
}

pub fn optional_field(
  key: String,
  field_schema: Schema(a),
  default: a,
  get: fn(final) -> a,
  next: fn(a) -> Schema(final),
) -> Schema(final) {
  schema.optional_field(key, field_schema, default, get, next)
}

pub fn done(value: a) -> Schema(a) {
  schema.done(value)
}

// --- Union / Lazy / Transform / Brand ---

pub fn tagged_union(
  discriminator: String,
  get_tag: fn(a) -> String,
  variants: List(#(String, Schema(a))),
) -> Schema(a) {
  schema.tagged_union(discriminator, get_tag, variants)
}

pub fn lazy(f: fn() -> Schema(a)) -> Schema(a) {
  schema.lazy(f)
}

pub fn transform(
  s: Schema(a),
  name: String,
  forward: fn(a) -> Result(b, String),
  backward: fn(b) -> a,
  dummy: fn() -> b,
) -> Schema(b) {
  schema.transform(s, name, forward, backward, dummy)
}

pub fn brand(
  base: Schema(a),
  name: String,
  wrap: fn(a) -> b,
  unwrap: fn(b) -> a,
) -> Schema(b) {
  schema.brand(base, name, wrap, unwrap)
}

// --- Execution ---

pub fn decode(s: Schema(a), v: Value) -> Result(a, List(Error)) {
  schema.decode(s, v)
}

pub fn encode(s: Schema(a), v: a) -> Value {
  schema.encode(s, v)
}

pub fn to_ast(s: Schema(a)) -> Ast {
  schema.to_ast(s)
}
