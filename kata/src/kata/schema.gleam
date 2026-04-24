import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import kata/ast.{
  type Ast, AstBool, AstBrand, AstDict, AstFloat, AstInt, AstLazy, AstList,
  AstObject, AstOption, AstString, AstTransformed, AstUnion, FieldSpec,
}
import kata/error.{type Error, Index, Key, Variant}
import kata/value.{
  type Value, VBool, VFloat, VInt, VList, VNull, VObject, VString,
}

/// Opaque bidirectional schema type.
/// Holds decode, encode, ast, and dummy functions.
pub opaque type Schema(a) {
  Schema(
    decode: fn(Value) -> Result(a, List(Error)),
    encode: fn(a) -> Value,
    ast: Ast,
    dummy: fn() -> a,
  )
}

// --- Execution ---

/// Decode a Value into a typed value using the schema
pub fn decode(schema: Schema(a), value: Value) -> Result(a, List(Error)) {
  schema.decode(value)
}

/// Encode a typed value into a Value using the schema
pub fn encode(schema: Schema(a), value: a) -> Value {
  schema.encode(value)
}

/// Get the AST for introspection
pub fn to_ast(schema: Schema(a)) -> Ast {
  schema.ast
}

// --- Smart constructors ---
// Validate a raw value through a schema (e.g. brand + refine).
// Useful for building smart constructors for opaque types.

/// Construct a validated value from a String.
pub fn from_string(
  schema: Schema(a),
  value: String,
) -> Result(a, List(Error)) {
  schema.decode(VString(value))
}

/// Construct a validated value from an Int.
pub fn from_int(schema: Schema(a), value: Int) -> Result(a, List(Error)) {
  schema.decode(VInt(value))
}

/// Construct a validated value from a Float.
pub fn from_float(
  schema: Schema(a),
  value: Float,
) -> Result(a, List(Error)) {
  schema.decode(VFloat(value))
}

/// Construct a validated value from a Bool.
pub fn from_bool(schema: Schema(a), value: Bool) -> Result(a, List(Error)) {
  schema.decode(VBool(value))
}

// --- Primitives ---

pub fn string() -> Schema(String) {
  Schema(
    decode: fn(v) {
      case v {
        VString(s) -> Ok(s)
        other -> type_mismatch_error("string", other)
      }
    },
    encode: fn(s) { VString(s) },
    ast: AstString([]),
    dummy: fn() { "" },
  )
}

pub fn int() -> Schema(Int) {
  Schema(
    decode: fn(v) {
      case v {
        VInt(n) -> Ok(n)
        other -> type_mismatch_error("int", other)
      }
    },
    encode: fn(n) { VInt(n) },
    ast: AstInt([]),
    dummy: fn() { 0 },
  )
}

pub fn float() -> Schema(Float) {
  Schema(
    decode: fn(v) {
      case v {
        VFloat(f) -> Ok(f)
        other -> type_mismatch_error("float", other)
      }
    },
    encode: fn(f) { VFloat(f) },
    ast: AstFloat([]),
    dummy: fn() { 0.0 },
  )
}

pub fn bool() -> Schema(Bool) {
  Schema(
    decode: fn(v) {
      case v {
        VBool(b) -> Ok(b)
        other -> type_mismatch_error("bool", other)
      }
    },
    encode: fn(b) { VBool(b) },
    ast: AstBool,
    dummy: fn() { False },
  )
}

// --- Containers ---

pub fn list(item: Schema(a)) -> Schema(List(a)) {
  Schema(
    decode: fn(v) {
      case v {
        VList(items) -> decode_list_with_index(items, item.decode, 0, [], [])
        other -> type_mismatch_error("list", other)
      }
    },
    encode: fn(xs) { VList(list.map(xs, item.encode)) },
    ast: AstList(item.ast),
    dummy: fn() { [] },
  )
}

pub fn optional(inner: Schema(a)) -> Schema(Option(a)) {
  Schema(
    decode: fn(v) {
      case v {
        VNull -> Ok(None)
        _ -> inner.decode(v) |> result.map(Some)
      }
    },
    encode: fn(opt) {
      case opt {
        Some(a) -> inner.encode(a)
        None -> VNull
      }
    },
    ast: AstOption(inner.ast),
    dummy: fn() { None },
  )
}

pub fn dict(
  key_schema: Schema(k),
  val_schema: Schema(v),
) -> Schema(dict.Dict(k, v)) {
  Schema(
    decode: fn(val) {
      case val {
        VObject(entries) ->
          decode_dict_entries(entries, key_schema, val_schema, [], [])
        other -> type_mismatch_error("object", other)
      }
    },
    encode: fn(d) {
      let entries =
        dict.to_list(d)
        |> list.map(fn(pair) {
          #(
            value_to_key_string(key_schema.encode(pair.0)),
            val_schema.encode(pair.1),
          )
        })
      VObject(entries)
    },
    ast: AstDict(key_schema.ast, val_schema.ast),
    dummy: fn() { dict.new() },
  )
}

// --- Record Builder ---

/// Define a field in an object schema.
/// - key: field name
/// - field_schema: schema for the field value
/// - get: extract field from the final record (for encode)
/// - next: continuation receiving the decoded field value
pub fn field(
  key: String,
  field_schema: Schema(a),
  get: fn(final) -> a,
  next: fn(a) -> Schema(final),
) -> Schema(final) {
  // For lazy field schemas (recursive), defer inner computation to avoid
  // infinite recursion. For non-lazy schemas, eagerly compute for full AST.
  case field_schema.ast {
    AstLazy(_) -> field_deferred(key, field_schema, get, next, False)
    _ -> field_eager(key, field_schema, get, next, False)
  }
}

fn field_eager(
  key: String,
  field_schema: Schema(a),
  get: fn(final) -> a,
  next: fn(a) -> Schema(final),
  is_optional: Bool,
) -> Schema(final) {
  // Evaluate inner schema eagerly for AST construction
  let inner = next(field_schema.dummy())

  let combined_ast = case inner.ast {
    AstObject(fields) ->
      AstObject([FieldSpec(key, field_schema.ast, is_optional), ..fields])
    _ -> AstObject([FieldSpec(key, field_schema.ast, is_optional)])
  }

  Schema(
    decode: fn(v: Value) -> Result(final, List(Error)) {
      field_decode(v, key, field_schema, next)
    },
    encode: fn(final_value: final) -> Value {
      field_encode(final_value, key, field_schema, get, next)
    },
    ast: combined_ast,
    dummy: fn() { inner.dummy() },
  )
}

fn field_deferred(
  key: String,
  field_schema: Schema(a),
  get: fn(final) -> a,
  next: fn(a) -> Schema(final),
  is_optional: Bool,
) -> Schema(final) {
  // Don't eagerly compute next(dummy) — would cause infinite recursion
  // for recursive schemas via lazy
  Schema(
    decode: fn(v: Value) -> Result(final, List(Error)) {
      field_decode(v, key, field_schema, next)
    },
    encode: fn(final_value: final) -> Value {
      field_encode(final_value, key, field_schema, get, next)
    },
    // For lazy fields, include only this field in AST (remaining fields
    // can't be computed without triggering recursion)
    ast: AstObject([FieldSpec(key, field_schema.ast, is_optional)]),
    // Defer dummy computation — only called when explicitly requested
    dummy: fn() { next(field_schema.dummy()).dummy() },
  )
}

fn field_decode(
  v: Value,
  key: String,
  field_schema: Schema(a),
  next: fn(a) -> Schema(final),
) -> Result(final, List(Error)) {
  case v {
    VObject(entries) -> {
      case list.key_find(entries, key) {
        Ok(field_value) -> {
          case field_schema.decode(field_value) {
            Ok(a) -> {
              let next_schema = next(a)
              // Pass the full object value, not just the field
              next_schema.decode(v)
            }
            Error(errs) -> Error(error.prepend_path(errs, Key(key)))
          }
        }
        Error(_) ->
          Error([
            error.Error(
              path: [Key(key)],
              issue: error.MissingField(key),
              schema_name: None,
            ),
          ])
      }
    }
    other -> type_mismatch_error("object", other)
  }
}

fn field_encode(
  final_value: final,
  key: String,
  field_schema: Schema(a),
  get: fn(final) -> a,
  next: fn(a) -> Schema(final),
) -> Value {
  let field_value = field_schema.encode(get(final_value))
  // Compute inner at runtime using the real extracted value
  // (avoids needing dummy, safe for recursive schemas)
  let inner = next(get(final_value))
  case inner.encode(final_value) {
    VObject(rest) -> VObject([#(key, field_value), ..rest])
    _ -> VObject([#(key, field_value)])
  }
}

/// Optional field with a default value when missing.
pub fn optional_field(
  key: String,
  field_schema: Schema(a),
  default: a,
  get: fn(final) -> a,
  next: fn(a) -> Schema(final),
) -> Schema(final) {
  // Wrap next to handle the optional decode logic
  let optional_next = fn(a) { next(a) }

  let decode_fn = fn(v: Value) -> Result(final, List(Error)) {
    case v {
      VObject(entries) -> {
        case list.key_find(entries, key) {
          Ok(VNull) -> {
            let next_schema = optional_next(default)
            next_schema.decode(v)
          }
          Ok(field_value) -> {
            case field_schema.decode(field_value) {
              Ok(a) -> {
                let next_schema = optional_next(a)
                next_schema.decode(v)
              }
              Error(errs) -> Error(error.prepend_path(errs, Key(key)))
            }
          }
          Error(_) -> {
            let next_schema = optional_next(default)
            next_schema.decode(v)
          }
        }
      }
      other -> type_mismatch_error("object", other)
    }
  }

  case field_schema.ast {
    AstLazy(_) ->
      Schema(
        decode: decode_fn,
        encode: fn(final_value: final) -> Value {
          field_encode(final_value, key, field_schema, get, next)
        },
        ast: AstObject([FieldSpec(key, field_schema.ast, True)]),
        dummy: fn() { next(field_schema.dummy()).dummy() },
      )
    _ -> {
      let inner = next(field_schema.dummy())
      let combined_ast = case inner.ast {
        AstObject(fields) ->
          AstObject([FieldSpec(key, field_schema.ast, True), ..fields])
        _ -> AstObject([FieldSpec(key, field_schema.ast, True)])
      }
      Schema(
        decode: decode_fn,
        encode: fn(final_value: final) -> Value {
          field_encode(final_value, key, field_schema, get, next)
        },
        ast: combined_ast,
        dummy: fn() { inner.dummy() },
      )
    }
  }
}

/// Terminal combinator for record builder.
pub fn done(value: a) -> Schema(a) {
  Schema(
    decode: fn(_v) { Ok(value) },
    encode: fn(_a) { VObject([]) },
    ast: AstObject([]),
    dummy: fn() { value },
  )
}

// --- Tagged Union ---

/// Discriminated union schema.
/// - discriminator: field name holding the tag
/// - get_tag: extract tag string from a value (for encode)
/// - variants: list of (tag, schema) pairs
pub fn tagged_union(
  discriminator: String,
  get_tag: fn(a) -> String,
  variants: List(#(String, Schema(a))),
) -> Schema(a) {
  let variant_asts = list.map(variants, fn(pair) { #(pair.0, { pair.1 }.ast) })
  let variant_tags = list.map(variants, fn(pair) { pair.0 })

  Schema(
    decode: fn(v) {
      case v {
        VObject(entries) -> {
          case list.key_find(entries, discriminator) {
            Ok(VString(tag)) -> {
              case list.key_find(variants, tag) {
                Ok(variant_schema) -> {
                  case variant_schema.decode(v) {
                    Ok(a) -> Ok(a)
                    Error(errs) -> Error(error.prepend_path(errs, Variant(tag)))
                  }
                }
                Error(_) ->
                  Error([
                    error.Error(
                      path: [],
                      issue: error.UnionNoMatch(
                        discriminator:,
                        tried: variant_tags,
                        got: tag,
                      ),
                      schema_name: None,
                    ),
                  ])
              }
            }
            Ok(other) ->
              Error([
                error.Error(
                  path: [Key(discriminator)],
                  issue: error.TypeMismatch(
                    expected: "string",
                    got: value.classify(other),
                  ),
                  schema_name: None,
                ),
              ])
            Error(_) ->
              Error([
                error.Error(
                  path: [Key(discriminator)],
                  issue: error.MissingField(discriminator),
                  schema_name: None,
                ),
              ])
          }
        }
        other -> type_mismatch_error("object", other)
      }
    },
    encode: fn(a) {
      let tag = get_tag(a)
      case list.key_find(variants, tag) {
        Ok(variant_schema) -> {
          case variant_schema.encode(a) {
            VObject(fields) ->
              VObject([#(discriminator, VString(tag)), ..fields])
            other -> other
          }
        }
        Error(_) -> VNull
      }
    },
    ast: AstUnion(discriminator, variant_asts),
    dummy: fn() {
      case variants {
        [#(_, first_schema), ..] -> first_schema.dummy()
        [] -> panic as "tagged_union requires at least one variant"
      }
    },
  )
}

// --- Lazy (recursive schemas) ---

pub fn lazy(f: fn() -> Schema(a)) -> Schema(a) {
  Schema(
    decode: fn(v) { f().decode(v) },
    encode: fn(a) { f().encode(a) },
    ast: AstLazy(fn() { f().ast }),
    dummy: fn() { f().dummy() },
  )
}

// --- Transform (bidirectional) ---

pub fn transform(
  schema: Schema(a),
  name: String,
  forward: fn(a) -> Result(b, String),
  backward: fn(b) -> a,
  dummy: fn() -> b,
) -> Schema(b) {
  Schema(
    decode: fn(v) {
      case schema.decode(v) {
        Ok(a) ->
          case forward(a) {
            Ok(b) -> Ok(b)
            Error(msg) -> refinement_failed_error(name, msg)
          }
        Error(errs) -> Error(errs)
      }
    },
    encode: fn(b) { schema.encode(backward(b)) },
    ast: AstTransformed(Some(name), schema.ast),
    dummy: dummy,
  )
}

// --- Brand (nominal typing helper) ---

pub fn brand(
  base: Schema(a),
  name: String,
  wrap: fn(a) -> b,
  unwrap: fn(b) -> a,
) -> Schema(b) {
  Schema(
    decode: fn(v) { base.decode(v) |> result.map(wrap) },
    encode: fn(b) { base.encode(unwrap(b)) },
    ast: AstBrand(name, base.ast),
    dummy: fn() { wrap(base.dummy()) },
  )
}

// --- Refinement helpers (used by kata/refine) ---

/// Add a string refinement to a Schema(String).
pub fn refine_string(
  s: Schema(String),
  ref: ast.StringRef,
  check: fn(String) -> Result(String, List(Error)),
) -> Schema(String) {
  Schema(
    decode: fn(v) {
      case s.decode(v) {
        Ok(str) -> check(str)
        Error(errs) -> Error(errs)
      }
    },
    encode: s.encode,
    ast: case s.ast {
      AstString(refs) -> AstString([ref, ..refs])
      other -> other
    },
    dummy: s.dummy,
  )
}

/// Add an int refinement to a Schema(Int).
pub fn refine_int(
  s: Schema(Int),
  ref: ast.IntRef,
  check: fn(Int) -> Result(Int, List(Error)),
) -> Schema(Int) {
  Schema(
    decode: fn(v) {
      case s.decode(v) {
        Ok(n) -> check(n)
        Error(errs) -> Error(errs)
      }
    },
    encode: s.encode,
    ast: case s.ast {
      AstInt(refs) -> AstInt([ref, ..refs])
      other -> other
    },
    dummy: s.dummy,
  )
}

/// Add a float refinement to a Schema(Float).
pub fn refine_float(
  s: Schema(Float),
  ref: ast.FloatRef,
  check: fn(Float) -> Result(Float, List(Error)),
) -> Schema(Float) {
  Schema(
    decode: fn(v) {
      case s.decode(v) {
        Ok(f) -> check(f)
        Error(errs) -> Error(errs)
      }
    },
    encode: s.encode,
    ast: case s.ast {
      AstFloat(refs) -> AstFloat([ref, ..refs])
      other -> other
    },
    dummy: s.dummy,
  )
}

// --- Internal helpers ---

fn type_mismatch_error(expected: String, got: Value) -> Result(a, List(Error)) {
  Error([
    error.Error(
      path: [],
      issue: error.TypeMismatch(expected:, got: value.classify(got)),
      schema_name: None,
    ),
  ])
}

fn refinement_failed_error(
  name: String,
  message: String,
) -> Result(a, List(Error)) {
  Error([
    error.Error(
      path: [],
      issue: error.RefinementFailed(name:, message:),
      schema_name: None,
    ),
  ])
}

/// Decode list items with index-based error paths.
/// Accumulates all errors across all elements.
fn decode_list_with_index(
  items: List(Value),
  decoder: fn(Value) -> Result(a, List(Error)),
  index: Int,
  acc_ok: List(a),
  acc_errors: List(Error),
) -> Result(List(a), List(Error)) {
  case items {
    [] -> {
      case acc_errors {
        [] -> Ok(list.reverse(acc_ok))
        _ -> Error(acc_errors)
      }
    }
    [item, ..rest] -> {
      case decoder(item) {
        Ok(a) ->
          decode_list_with_index(
            rest,
            decoder,
            index + 1,
            [a, ..acc_ok],
            acc_errors,
          )
        Error(errs) -> {
          let path_errs = error.prepend_path(errs, Index(index))
          decode_list_with_index(
            rest,
            decoder,
            index + 1,
            acc_ok,
            list.append(acc_errors, path_errs),
          )
        }
      }
    }
  }
}

/// Decode dict entries from VObject key-value pairs
fn decode_dict_entries(
  entries: List(#(String, Value)),
  key_schema: Schema(k),
  val_schema: Schema(v),
  acc_ok: List(#(k, v)),
  acc_errors: List(Error),
) -> Result(dict.Dict(k, v), List(Error)) {
  case entries {
    [] -> {
      case acc_errors {
        [] -> Ok(dict.from_list(list.reverse(acc_ok)))
        _ -> Error(acc_errors)
      }
    }
    [#(raw_key, raw_val), ..rest] -> {
      let key_result = key_schema.decode(VString(raw_key))
      let val_result = val_schema.decode(raw_val)
      case key_result, val_result {
        Ok(k), Ok(v) ->
          decode_dict_entries(
            rest,
            key_schema,
            val_schema,
            [#(k, v), ..acc_ok],
            acc_errors,
          )
        Error(k_errs), Error(v_errs) -> {
          let errs =
            list.append(
              error.prepend_path(k_errs, Key(raw_key)),
              error.prepend_path(v_errs, Key(raw_key)),
            )
          decode_dict_entries(
            rest,
            key_schema,
            val_schema,
            acc_ok,
            list.append(acc_errors, errs),
          )
        }
        Error(k_errs), _ ->
          decode_dict_entries(
            rest,
            key_schema,
            val_schema,
            acc_ok,
            list.append(acc_errors, error.prepend_path(k_errs, Key(raw_key))),
          )
        _, Error(v_errs) ->
          decode_dict_entries(
            rest,
            key_schema,
            val_schema,
            acc_ok,
            list.append(acc_errors, error.prepend_path(v_errs, Key(raw_key))),
          )
      }
    }
  }
}

/// Extract string from Value for dict key encoding
fn value_to_key_string(v: Value) -> String {
  case v {
    VString(s) -> s
    _ -> panic as "dict key must encode to VString"
  }
}
