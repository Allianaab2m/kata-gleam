# kata Internal Architecture

This document is for **adapter developers** and contributors who want to understand kata's internal structure. It covers the Value intermediate representation, AST system, Schema internals, Format trait, and error propagation.

## Table of Contents

- [Overview](#overview)
- [Data Flow](#data-flow)
- [Value: The Intermediate Representation](#value-the-intermediate-representation)
- [Schema Internals](#schema-internals)
- [AST System](#ast-system)
- [Error System](#error-system)
- [Format Trait](#format-trait)
- [Writing a Format Adapter](#writing-a-format-adapter)
- [Refinement Internals](#refinement-internals)
- [Module Dependency Graph](#module-dependency-graph)

---

## Overview

kata's architecture follows a **hub-and-spoke model** with `Value` as the central hub:

```
Wire Format (JSON, Form, YAML, ...)
        |                   ^
        | parse             | serialize
        v                   |
      Value  <--- hub --->  Value
        |                   ^
        | decode            | encode
        v                   |
   Gleam Type (User, Order, ...)
```

This design means:
- **Schemas** only need to know about `Value`, not about wire formats.
- **Format adapters** only need to convert between their format and `Value`, not about schemas.
- Adding a new wire format requires no changes to existing schemas.

---

## Data Flow

### Decoding (wire format -> Gleam type)

```
raw input --[Format.parse]--> Value --[Schema.decode]--> Result(a, List(Error))
```

1. The format adapter's `parse` function converts the raw input (e.g. JSON string) into a `Value` tree.
2. The schema's `decode` function walks the `Value` tree and produces a typed Gleam value, or a list of structured errors.

### Encoding (Gleam type -> wire format)

```
typed value --[Schema.encode]--> Value --[Format.serialize]--> Result(raw, String)
```

1. The schema's `encode` function converts the typed value into a `Value` tree.
2. The format adapter's `serialize` function converts the `Value` tree back into the wire format.

---

## Value: The Intermediate Representation

Defined in `kata/value.gleam`:

```gleam
pub type Value {
  VNull
  VBool(Bool)
  VInt(Int)
  VFloat(Float)
  VString(String)
  VList(List(Value))
  VObject(List(#(String, Value)))
}
```

### Design Decisions

**`VObject` uses `List(#(String, Value))`, not `Dict`:**
- Preserves insertion order (important for some wire formats).
- On decode, the first occurrence of a duplicate key wins.
- On encode, schemas produce fields in definition order.

**`VInt` and `VFloat` are separate:**
- Some formats (JSON) distinguish integers from floats. Others (form data) do not.
- The `coerce` module bridges this gap for string-based formats.

**`VNull` is explicit:**
- Allows distinguishing "field is absent" from "field is null".
- `optional` schemas treat both as `None`.

### Utility

```gleam
pub fn classify(v: Value) -> String
```

Returns a human-readable type name: `"null"`, `"bool"`, `"int"`, `"float"`, `"string"`, `"list"`, `"object"`. Used in error messages for `TypeMismatch`.

### Implementing `parse` for Your Format

Your adapter must convert its raw representation into this `Value` tree. Key rules:

1. **Map native nulls to `VNull`.**
2. **Map booleans to `VBool`.**
3. **Map integers to `VInt` and floats to `VFloat`** if your format distinguishes them. If your format is string-based (all values are strings), map everything to `VString` and rely on `coerce` schemas.
4. **Map arrays/lists to `VList`.**
5. **Map objects/maps to `VObject`** as `List(#(String, Value))`. Preserve key order if possible.

---

## Schema Internals

Defined in `kata/schema.gleam`:

```gleam
pub opaque type Schema(a) {
  Schema(
    decode: fn(Value) -> Result(a, List(Error)),
    encode: fn(a) -> Value,
    ast: Ast,
    dummy: fn() -> a,
  )
}
```

A schema is an opaque bundle of four functions/values:

| Field | Purpose |
|---|---|
| `decode` | `Value -> Result(a, List(Error))` — parse and validate a Value tree |
| `encode` | `a -> Value` — convert a typed value back to Value |
| `ast` | `Ast` — structural description for introspection |
| `dummy` | `fn() -> a` — produce a default value (used during AST construction for field chains) |

### The `dummy` Function

The `dummy` field deserves special attention. It exists to solve a chicken-and-egg problem in the field builder pattern:

When building a record schema like:
```gleam
use name <- kata.field("name", kata.string(), fn(u: User) { u.name })
use age <- kata.field("age", kata.int(), fn(u: User) { u.age })
kata.done(User(name:, age:))
```

The AST for the full schema must be constructed eagerly. To do this, kata calls the continuation chain with dummy values to discover the complete field structure:

1. `field("name", string(), ...)` needs to call the continuation with a dummy `String` to discover what fields come next.
2. The continuation returns another `field(...)`, which again needs a dummy value.
3. This repeats until `done(...)` is reached.

For primitive schemas, dummies are trivial (`""`, `0`, `0.0`, `False`). For `brand` and `transform`, the user provides a dummy function. For `lazy`, the dummy is deferred to avoid infinite recursion.

### Field Building in Detail

The `field` function:
1. **Decode:** Looks up `key` in a `VObject`, decodes the value with `schema`, then passes the result to `next`.
2. **Encode:** Calls `get(final_value)` to extract the field, encodes it with `schema`, prepends `#(key, encoded)` to the object.
3. **AST:** Evaluates the continuation with a dummy value to discover remaining fields. Collects all `FieldSpec` entries into an `AstObject`.

The `optional_field` function works similarly but:
- On decode: if the key is missing or the value is `VNull`, uses `default` instead of failing.
- On AST: marks the `FieldSpec` with `optional: True`.

### Tagged Union Internals

`tagged_union(discriminator, get_tag, variants)`:

**Decode:**
1. Expects a `VObject`.
2. Looks up the `discriminator` field (e.g. `"kind"`).
3. Matches the tag string against the variant list.
4. Decodes with the matching variant's schema.
5. If no variant matches, returns `UnionNoMatch` error.

**Encode:**
1. Calls `get_tag(value)` to determine the tag.
2. Finds the matching variant schema.
3. Encodes with that schema (producing a `VObject`).
4. Prepends `#(discriminator, VString(tag))` to the object.

**AST:**
- Produces `AstUnion(discriminator, variants)` where each variant is `#(tag, ast)`.
- Each variant's AST is computed by calling `to_ast` on the variant schema.

---

## AST System

Defined in `kata/ast.gleam`:

```gleam
pub type Ast {
  AstString(refinements: List(StringRef))
  AstInt(refinements: List(IntRef))
  AstFloat(refinements: List(FloatRef))
  AstBool
  AstNull
  AstList(item: Ast)
  AstDict(key: Ast, value: Ast)
  AstOption(inner: Ast)
  AstObject(fields: List(FieldSpec))
  AstUnion(discriminator: String, variants: List(#(String, Ast)))
  AstLazy(fn() -> Ast)
  AstTransformed(name: Option(String), base: Ast)
  AstBrand(name: String, base: Ast)
}

pub type FieldSpec {
  FieldSpec(key: String, ast: Ast, optional: Bool)
}
```

### Purpose

The AST is **public** and designed for ecosystem tools:

- **JSON Schema generation** (`kata/json_schema`): walks the AST to produce JSON Schema Draft 7.
- **Form generation**: walk the AST to build form fields with appropriate input types and validation attributes.
- **API documentation**: extract field names, types, constraints, and optionality.
- **Code generation**: generate types or validators in other languages.

### Refinement Types

Refinements are stored directly in the AST as metadata:

```gleam
pub type StringRef {
  MinLength(Int)
  MaxLength(Int)
  Pattern(String)
}

pub type IntRef {
  IntMin(Int)
  IntMax(Int)
}

pub type FloatRef {
  FloatMin(Float)
  FloatMax(Float)
}
```

This allows ecosystem tools to extract constraints without executing the schema.

### Wrapper Nodes

**`AstBrand(name, base)`:**
- Wraps the base AST with a brand name.
- Tools can use the name for display (e.g. `"Email"`, `"UserId"`) and unwrap to `base` to see the underlying structure.

**`AstTransformed(name, base)`:**
- Wraps the base AST for a `transform` schema.
- `name` is `Some("...")` if the transform was named, `None` otherwise.
- Tools should typically look through to `base` for structural information.

**`AstLazy(thunk)`:**
- Defers AST evaluation for recursive schemas.
- **Tools must handle this:** call the thunk to get the real AST, but guard against infinite recursion (e.g. with a visited set or depth limit).

### Walking the AST

Example: extracting all field names from an object schema.

```gleam
fn field_names(ast: Ast) -> List(String) {
  case ast {
    AstObject(fields) -> list.map(fields, fn(f) { f.key })
    AstBrand(_, base) -> field_names(base)
    AstTransformed(_, base) -> field_names(base)
    AstLazy(thunk) -> field_names(thunk())
    _ -> []
  }
}
```

---

## Error System

Defined in `kata/error.gleam`:

```gleam
pub type Error {
  Error(
    path: List(PathSegment),
    issue: Issue,
    schema_name: Option(String),
  )
}

pub type PathSegment {
  Key(String)
  Index(Int)
  Variant(String)
}

pub type Issue {
  TypeMismatch(expected: String, got: String)
  MissingField(name: String)
  RefinementFailed(name: String, message: String)
  UnionNoMatch(discriminator: String, tried: List(String), got: String)
  Custom(message: String)
}
```

### Path Construction

Errors are created at the point of failure with an empty path. As they bubble up through nested schemas, each layer prepends its path segment:

```
// Inner error (created at point of failure):
Error(path: [], issue: TypeMismatch("string", "int"), schema_name: None)

// After bubbling through field("name", ...):
Error(path: [Key("name")], issue: TypeMismatch("string", "int"), schema_name: None)

// After bubbling through field("user", ...):
Error(path: [Key("user"), Key("name")], issue: TypeMismatch("string", "int"), schema_name: None)

// Formatted: "$.user.name: expected string, got int"
```

The `prepend_path(errors, segment)` utility handles this.

### Error Accumulation Strategy

- **Lists:** All items are decoded. Errors from each item are accumulated with `Index(n)` path segments.
- **Objects:** Required fields that are missing produce `MissingField` errors. Other field errors are accumulated.
- **Unions:** Only the matching variant is decoded. If no variant matches, a single `UnionNoMatch` error is produced.

---

## Format Trait

Defined in `kata/format.gleam`:

```gleam
pub type Format(raw) {
  Format(
    name: String,
    parse: fn(raw) -> Result(Value, String),
    serialize: fn(Value) -> Result(raw, String),
    mode: ParseMode,
  )
}

pub type ParseMode {
  Strict
  Coerce
}
```

### Fields

| Field | Description |
|---|---|
| `name` | Human-readable format name (e.g. `"json"`, `"form"`) — used in error messages |
| `parse` | Converts raw input to `Value` tree, or returns an error string |
| `serialize` | Converts `Value` tree to raw output, or returns an error string |
| `mode` | `Strict` (types must match exactly) or `Coerce` (string coercion allowed) |

### `ParseMode`

The `mode` field signals to schema users which type of primitives they should use:

- **`Strict`** (e.g. JSON): Use `kata.int()`, `kata.float()`, `kata.bool()` — values arrive as their native types.
- **`Coerce`** (e.g. form data, env vars): Use `coerce.int()`, `coerce.float()`, `coerce.bool()` — values arrive as strings and need coercion.

The `mode` is informational — it's up to the schema author to choose the right primitives. kata does not automatically switch between coerced and strict modes.

### `DecodeError`

```gleam
pub type DecodeError {
  ParseError(message: String)
  SchemaError(errors: List(Error))
}
```

`format.decode` separates the two failure modes:
- `ParseError`: the raw input was malformed (e.g. invalid JSON syntax).
- `SchemaError`: the input parsed successfully but didn't match the schema.

This distinction lets callers provide appropriate error messages (e.g. "invalid JSON" vs "field X is missing").

---

## Writing a Format Adapter

To add support for a new wire format (e.g. YAML, TOML, MessagePack), you need to:

### 1. Create a New Gleam Package

```
gleam new kata_yaml
```

Add `kata` as a dependency in `gleam.toml`.

### 2. Implement `parse` and `serialize`

Map between your format's native representation and `Value`:

```gleam
import kata/value.{type Value, VBool, VFloat, VInt, VList, VNull, VObject, VString}

pub fn parse(yaml_string: String) -> Result(Value, String) {
  // Use a YAML parsing library to parse the string.
  // Convert each YAML node to the corresponding Value variant:
  //   YAML null       -> VNull
  //   YAML boolean    -> VBool(b)
  //   YAML integer    -> VInt(n)
  //   YAML float      -> VFloat(f)
  //   YAML string     -> VString(s)
  //   YAML sequence   -> VList(items)   (recursively convert each item)
  //   YAML mapping    -> VObject(pairs) (recursively convert each value)
  todo
}

pub fn serialize(value: Value) -> Result(String, String) {
  // Convert Value back to YAML string:
  //   VNull       -> YAML null
  //   VBool(b)    -> YAML boolean
  //   VInt(n)     -> YAML integer
  //   VFloat(f)   -> YAML float
  //   VString(s)  -> YAML string
  //   VList(items) -> YAML sequence
  //   VObject(pairs) -> YAML mapping
  todo
}
```

### 3. Create the `Format` Record

```gleam
import kata/format.{type Format, Format, Strict}

pub fn format() -> Format(String) {
  Format(
    name: "yaml",
    parse: parse,
    serialize: fn(v) { Ok(serialize_to_string(v)) },
    mode: Strict,  // or Coerce if your format is string-based
  )
}
```

### 4. (Optional) Add Convenience Functions

```gleam
import kata/error.{type Error}

pub type YamlError {
  ParseError(message: String)
  SchemaError(errors: List(Error))
}

pub fn decode_yaml(
  schema: kata.Schema(a),
  yaml_string: String,
) -> Result(a, YamlError) {
  case parse(yaml_string) {
    Error(msg) -> Error(ParseError(msg))
    Ok(value) ->
      case kata.decode(schema, value) {
        Error(errs) -> Error(SchemaError(errs))
        Ok(result) -> Ok(result)
      }
  }
}

pub fn encode_yaml(schema: kata.Schema(a), value: a) -> String {
  let v = kata.encode(schema, value)
  serialize_to_string(v)
}
```

### 5. Choosing `ParseMode`

- If your format has native types (null, bool, int, float, string, array, object) — use `Strict`.
- If your format is string-based (e.g. form data where `age=30` arrives as `"30"`) — use `Coerce`.

When your format uses `Coerce`, users should use `coerce.int()`, `coerce.float()`, and `coerce.bool()` instead of the strict primitives.

### Reference Implementation

See `kata_json` for a complete reference implementation:
- `kata_json/src/kata_json.gleam` — the JSON format adapter using `gleam/json` for parsing and `gleam/json` for serialization.

---

## Refinement Internals

Refinements are implemented via three internal functions in `kata/schema.gleam`:

```gleam
pub fn refine_string(schema, ref, check) -> Schema(String)
pub fn refine_int(schema, ref, check) -> Schema(Int)
pub fn refine_float(schema, ref, check) -> Schema(Float)
```

Each:
1. **Wraps the decode function:** after the base schema decodes, applies the `check` function. If it returns `Error(msg)`, produces a `RefinementFailed` error.
2. **Appends the refinement to the AST:** adds the `StringRef`/`IntRef`/`FloatRef` to the AST node's refinement list.
3. **Leaves encode unchanged:** refinements are decode-only.

The public API in `kata/refine.gleam` calls these internal functions with specific check implementations:

```gleam
pub fn min_length(schema: Schema(String), n: Int) -> Schema(String) {
  schema.refine_string(schema, ast.MinLength(n), fn(s) {
    case string.length(s) >= n {
      True -> Ok(Nil)
      False -> Error("must be at least " <> int.to_string(n) <> " characters")
    }
  })
}
```

---

## Module Dependency Graph

```
kata (public re-exports)
  |
  +-- kata/schema (core engine)
  |     |-- kata/value
  |     |-- kata/ast
  |     +-- kata/error
  |
  +-- kata/refine (validation)
  |     +-- kata/schema
  |
  +-- kata/coerce (string coercion)
  |     +-- kata/schema
  |
  +-- kata/format (adapter trait)
  |     |-- kata/schema
  |     +-- kata/error
  |
  +-- kata/json_schema (schema generation)
  |     +-- kata/ast
  |
  +-- kata/dynamic (FFI interop)
        +-- kata/value

kata_json (separate package)
  |-- kata
  |-- kata/value
  |-- kata/error
  +-- kata/format
```

**Key principle:** `kata/value` and `kata/ast` have no internal dependencies — they are pure data types. This makes them safe foundation modules that everything else can depend on.
