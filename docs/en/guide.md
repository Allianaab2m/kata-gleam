# kata API Guide

kata is a **bidirectional schema library for Gleam**. Define a single schema that handles both decoding (parsing) and encoding (serializing), across any wire format.

The name comes from the Japanese word **型** (kata), meaning "form" or "mold."

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Primitive Schemas](#primitive-schemas)
- [Container Schemas](#container-schemas)
- [Record (Object) Schemas](#record-object-schemas)
- [Tagged Unions](#tagged-unions)
- [Refinements](#refinements)
- [Brand (Opaque Types)](#brand-opaque-types)
- [Transform](#transform)
- [Recursive Schemas](#recursive-schemas)
- [Format Adapters](#format-adapters)
- [Smart Constructors](#smart-constructors)
- [JSON Schema Generation](#json-schema-generation)
- [Error Handling](#error-handling)
- [API Reference](#api-reference)

---

## Installation

Add kata (and any format adapter you need) to your `gleam.toml`:

```toml
[dependencies]
kata = ">= 0.1.0"
kata_json = ">= 0.1.0"   # if you need JSON support
```

## Quick Start

```gleam
import kata
import kata_json

// 1. Define your type
pub type User {
  User(name: String, age: Int)
}

// 2. Define the schema once — it handles both directions
fn user_schema() -> kata.Schema(User) {
  use name <- kata.field("name", kata.string(), fn(u: User) { u.name })
  use age <- kata.field("age", kata.int(), fn(u: User) { u.age })
  kata.done(User(name:, age:))
}

// 3. Decode from JSON
let json = "{\"name\":\"Alice\",\"age\":30}"
let assert Ok(user) = kata_json.decode_json(user_schema(), json)
// -> User("Alice", 30)

// 4. Encode back to JSON
let json_out = kata_json.encode_json(user_schema(), user)
// -> "{\"name\":\"Alice\",\"age\":30}"
```

---

## Primitive Schemas

kata provides schemas for the four primitive types:

| Function | Type | Accepts |
|---|---|---|
| `kata.string()` | `Schema(String)` | `VString` |
| `kata.int()` | `Schema(Int)` | `VInt` |
| `kata.float()` | `Schema(Float)` | `VFloat` |
| `kata.bool()` | `Schema(Bool)` | `VBool` |

```gleam
let s = kata.string()
let assert Ok("hello") = kata.decode(s, VString("hello"))

let encoded = kata.encode(s, "hello")
// -> VString("hello")
```

### Coerced Primitives

For string-based wire formats (form data, environment variables) where all values arrive as strings, use the coercion variants from `kata/coerce`:

| Function | Accepts |
|---|---|
| `coerce.int()` | `VInt` or `VString` parseable as int |
| `coerce.float()` | `VFloat`, `VInt`, or `VString` parseable as float |
| `coerce.bool()` | `VBool` or `VString("true"/"false")` |

```gleam
import kata/coerce

let s = coerce.int()
let assert Ok(42) = kata.decode(s, VString("42"))
let assert Ok(42) = kata.decode(s, VInt(42))
```

---

## Container Schemas

### List

```gleam
let int_list = kata.list(kata.int())

let encoded = kata.encode(int_list, [1, 2, 3])
// -> VList([VInt(1), VInt(2), VInt(3)])

let assert Ok([1, 2, 3]) = kata.decode(int_list, encoded)
```

### Optional

Wraps a schema so that `VNull` (or missing field) decodes as `None`:

```gleam
import gleam/option.{None, Some}

let opt = kata.optional(kata.string())

let assert Ok(Some("hi")) = kata.decode(opt, VString("hi"))
let assert Ok(None) = kata.decode(opt, VNull)
```

### Dict

Decodes/encodes key-value maps. Keys and values each have their own schema:

```gleam
let d = kata.dict(kata.string(), kata.int())

let input = VObject([#("x", VInt(1)), #("y", VInt(2))])
let assert Ok(result) = kata.decode(d, input)
// result == dict.from_list([#("x", 1), #("y", 2)])
```

---

## Record (Object) Schemas

Records are built using a continuation-passing pattern with `field`, `optional_field`, and `done`:

```gleam
pub type User {
  User(name: String, age: Int, bio: option.Option(String))
}

fn user_schema() -> kata.Schema(User) {
  // Required field: key, schema, getter (for encode), continuation
  use name <- kata.field("name", kata.string(), fn(u: User) { u.name })
  use age <- kata.field("age", kata.int(), fn(u: User) { u.age })
  // Optional field: key, schema, default, getter, continuation
  use bio <- kata.optional_field(
    "bio", kata.string(), option.None, fn(u: User) { u.bio },
  )
  kata.done(User(name:, age:, bio:))
}
```

### `kata.field(key, schema, get, next)`

Declares a **required** field.

| Parameter | Description |
|---|---|
| `key` | The field name in the wire format (e.g. `"name"`) |
| `schema` | Schema for this field's value |
| `get` | Getter function: extracts this field from the record (used for encoding) |
| `next` | Continuation: receives the decoded value and returns the rest of the schema |

### `kata.optional_field(key, schema, default, get, next)`

Declares an **optional** field. If the field is missing or `VNull`, `default` is used.

### `kata.done(value)`

Terminates the field chain and returns the constructed value.

### Nested Objects

Schemas compose naturally for nesting:

```gleam
pub type Profile {
  Profile(user: User, website: String)
}

fn profile_schema() -> kata.Schema(Profile) {
  use user <- kata.field("user", user_schema(), fn(p: Profile) { p.user })
  use website <- kata.field("website", kata.string(), fn(p: Profile) { p.website })
  kata.done(Profile(user:, website:))
}
```

---

## Tagged Unions

For sum types where a discriminator field determines the variant:

```gleam
pub type Shape {
  Circle(radius: Float)
  Rectangle(width: Float, height: Float)
}

fn shape_schema() -> kata.Schema(Shape) {
  kata.tagged_union(
    "kind",                          // discriminator field name
    fn(s: Shape) {                   // tag extractor (for encode)
      case s {
        Circle(_) -> "circle"
        Rectangle(_, _) -> "rectangle"
      }
    },
    [                                // variant list: #(tag, schema)
      #("circle", {
        use r <- kata.field("radius", kata.float(), fn(s: Shape) {
          case s { Circle(r) -> r, _ -> 0.0 }
        })
        kata.done(Circle(r))
      }),
      #("rectangle", {
        use w <- kata.field("width", kata.float(), fn(s: Shape) {
          case s { Rectangle(w, _) -> w, _ -> 0.0 }
        })
        use h <- kata.field("height", kata.float(), fn(s: Shape) {
          case s { Rectangle(_, h) -> h, _ -> 0.0 }
        })
        kata.done(Rectangle(w, h))
      }),
    ],
  )
}
```

**Decoding:** reads the discriminator field (`"kind"`), matches the tag to a variant schema, and decodes with that schema.

**Encoding:** calls the tag extractor to determine the tag, encodes with the matching schema, then injects the discriminator field.

Example JSON:
```json
{"kind": "circle", "radius": 5.0}
{"kind": "rectangle", "width": 3.0, "height": 4.0}
```

---

## Refinements

Add validation constraints to schemas without affecting encoding. Import `kata/refine`:

### String Refinements

```gleam
import kata/refine

let name_schema =
  kata.string()
  |> refine.min_length(1)
  |> refine.max_length(100)

let email_schema =
  kata.string()
  |> refine.email()

let code_schema =
  kata.string()
  |> refine.matches("^[A-Z]{3}-\\d{4}$")
```

### Int Refinements

```gleam
let age_schema =
  kata.int()
  |> refine.min(0)
  |> refine.max(150)
```

### Float Refinements

```gleam
let score_schema =
  kata.float()
  |> refine.float_min(0.0)
  |> refine.float_max(100.0)
```

Refinements are **composable** — you can chain multiple on the same schema. All constraints are checked during decoding, and failures are reported with `RefinementFailed` errors including the constraint details.

Refinements are also reflected in the **AST** and appear in generated **JSON Schema** output.

---

## Brand (Opaque Types)

`kata.brand` wraps a schema with a nominal type, useful for opaque "newtype" wrappers:

```gleam
pub type Email {
  Email(String)
}

fn email_schema() -> kata.Schema(Email) {
  kata.string()
  |> refine.email()
  |> kata.brand("Email", Email, fn(e: Email) {
    let Email(s) = e
    s
  })
}
```

| Parameter | Description |
|---|---|
| `name` | Brand name (appears in AST and JSON Schema as `title`) |
| `wrap` | Constructor: `a -> b` |
| `unwrap` | Extractor: `b -> a` |

The brand name is embedded in the AST (`AstBrand`) and surfaces in JSON Schema output as the `title` field.

---

## Transform

`kata.transform` applies a custom transformation during decode/encode:

```gleam
pub type Percent {
  Percent(Int)
}

fn percent_schema() -> kata.Schema(Percent) {
  kata.int()
  |> kata.transform(
    "Percent",
    fn(n) {                          // forward: decode direction
      case n >= 0 && n <= 100 {
        True -> Ok(Percent(n))
        False -> Error("must be 0-100")
      }
    },
    fn(p) { let Percent(n) = p; n }, // backward: encode direction
    fn() { Percent(0) },             // dummy value (for AST)
  )
}
```

| Parameter | Description |
|---|---|
| `name` | Transformation name (appears in AST) |
| `forward` | `a -> Result(b, String)` — decode direction |
| `backward` | `b -> a` — encode direction (must be inverse of forward) |
| `dummy` | `fn() -> b` — produces a dummy value for AST construction |

---

## Recursive Schemas

Use `kata.lazy` to break circular references:

```gleam
pub type Tree {
  Leaf(Int)
  Node(left: Tree, right: Tree)
}

fn tree_schema() -> kata.Schema(Tree) {
  kata.tagged_union(
    "kind",
    fn(t: Tree) {
      case t { Leaf(_) -> "leaf", Node(_, _) -> "node" }
    },
    [
      #("leaf", {
        use v <- kata.field("value", kata.int(), fn(t: Tree) {
          case t { Leaf(n) -> n, _ -> 0 }
        })
        kata.done(Leaf(v))
      }),
      #("node", {
        use l <- kata.field("left", kata.lazy(tree_schema), fn(t: Tree) {
          case t { Node(l, _) -> l, _ -> Leaf(0) }
        })
        use r <- kata.field("right", kata.lazy(tree_schema), fn(t: Tree) {
          case t { Node(_, r) -> r, _ -> Leaf(0) }
        })
        kata.done(Node(l, r))
      }),
    ],
  )
}
```

`kata.lazy(f)` takes a **thunk** (`fn() -> Schema(a)`) so the schema is only evaluated when needed, preventing infinite recursion.

---

## Format Adapters

kata is format-agnostic. The `Format` abstraction lets the same schema work with JSON, form data, or any other wire format.

### Using a Format

```gleam
import kata/format
import kata_json

// Decode
let result = format.decode(user_schema(), kata_json.format(), json_string)
case result {
  Ok(user) -> // success
  Error(format.ParseError(msg)) -> // invalid JSON syntax
  Error(format.SchemaError(errs)) -> // valid JSON, but didn't match schema
}

// Encode
let assert Ok(json) = format.encode(user_schema(), kata_json.format(), user)
```

The key benefit: `format.decode` distinguishes **parse errors** (bad syntax) from **schema errors** (valid data but wrong shape), via the `DecodeError` type:

```gleam
pub type DecodeError {
  ParseError(message: String)
  SchemaError(errors: List(Error))
}
```

### Convenience Functions (kata_json)

If you only need JSON, `kata_json` provides shorthand:

```gleam
import kata_json

let assert Ok(user) = kata_json.decode_json(user_schema(), json_string)
let json_out = kata_json.encode_json(user_schema(), user)
```

### Writing Your Own Adapter

See [Architecture: Writing a Format Adapter](architecture.md#writing-a-format-adapter) for details.

---

## Smart Constructors

Validate raw primitive values directly using a schema, without going through the intermediate `Value` representation:

```gleam
pub type Email {
  Email(String)
}

fn email_schema() -> kata.Schema(Email) {
  kata.string()
  |> refine.email()
  |> kata.brand("Email", Email, fn(e: Email) { let Email(s) = e; s })
}

// Smart constructor
pub fn new_email(s: String) -> Result(Email, List(kata.Error)) {
  kata.from_string(email_schema(), s)
}
```

Available smart constructors:

| Function | Input Type |
|---|---|
| `kata.from_string(schema, s)` | `String` |
| `kata.from_int(schema, n)` | `Int` |
| `kata.from_float(schema, f)` | `Float` |
| `kata.from_bool(schema, b)` | `Bool` |

Each wraps the primitive into a `Value`, runs it through the schema's decode, and returns the result. Useful for domain types that need validation at construction time.

---

## JSON Schema Generation

Generate JSON Schema (Draft 7) from any schema:

```gleam
import kata/json_schema

let schema_str = json_schema.to_json_schema(user_schema())
```

Output:
```json
{
  "type": "object",
  "properties": {
    "name": { "type": "string" },
    "age": { "type": "integer" }
  },
  "required": ["name", "age"]
}
```

Refinements and brands are reflected in the output:
- `min_length` / `max_length` -> `minLength` / `maxLength`
- `min` / `max` -> `minimum` / `maximum`
- `matches` -> `pattern`
- `brand` -> `title`

---

## Error Handling

Decode errors are structured and include precise path information:

```gleam
import kata/error

case kata.decode(user_schema(), bad_value) {
  Ok(user) -> // ...
  Error(errors) -> {
    // Format all errors as human-readable strings
    let msg = error.format_errors(errors)
    // -> "$.name: expected string, got int\n$.age: missing required field \"age\""
  }
}
```

### Error Structure

```gleam
pub type Error {
  Error(
    path: List(PathSegment),  // location in the data
    issue: Issue,             // what went wrong
    schema_name: Option(String),
  )
}
```

### Path Segments

| Variant | Meaning | Example |
|---|---|---|
| `Key(name)` | Object field | `$.user` |
| `Index(n)` | List element | `$.items[0]` |
| `Variant(tag)` | Union variant | `$.shape<circle>` |

### Issue Types

| Variant | When |
|---|---|
| `TypeMismatch(expected, got)` | Wrong value type (e.g. expected string, got int) |
| `MissingField(name)` | Required field not present |
| `RefinementFailed(name, message)` | Validation constraint violated |
| `UnionNoMatch(discriminator, tried, got)` | No union variant matched |
| `Custom(message)` | Custom error from `transform` |

---

## API Reference

### Core Module (`kata`)

#### Primitive Constructors
- `string() -> Schema(String)`
- `int() -> Schema(Int)`
- `float() -> Schema(Float)`
- `bool() -> Schema(Bool)`

#### Container Constructors
- `list(item: Schema(a)) -> Schema(List(a))`
- `optional(inner: Schema(a)) -> Schema(Option(a))`
- `dict(key_schema: Schema(k), val_schema: Schema(v)) -> Schema(Dict(k, v))`

#### Record Building
- `field(key: String, schema: Schema(a), get: fn(final) -> a, next: fn(a) -> Schema(final)) -> Schema(final)`
- `optional_field(key: String, schema: Schema(a), default: a, get: fn(final) -> a, next: fn(a) -> Schema(final)) -> Schema(final)`
- `done(value: a) -> Schema(a)`

#### Advanced Combinators
- `tagged_union(discriminator: String, get_tag: fn(a) -> String, variants: List(#(String, Schema(a)))) -> Schema(a)`
- `lazy(f: fn() -> Schema(a)) -> Schema(a)`
- `transform(schema: Schema(a), name: String, forward: fn(a) -> Result(b, String), backward: fn(b) -> a, dummy: fn() -> b) -> Schema(b)`
- `brand(base: Schema(a), name: String, wrap: fn(a) -> b, unwrap: fn(b) -> a) -> Schema(b)`

#### Execution
- `decode(schema: Schema(a), value: Value) -> Result(a, List(Error))`
- `encode(schema: Schema(a), value: a) -> Value`
- `to_ast(schema: Schema(a)) -> Ast`

#### Smart Constructors
- `from_string(schema: Schema(a), value: String) -> Result(a, List(Error))`
- `from_int(schema: Schema(a), value: Int) -> Result(a, List(Error))`
- `from_float(schema: Schema(a), value: Float) -> Result(a, List(Error))`
- `from_bool(schema: Schema(a), value: Bool) -> Result(a, List(Error))`

### Refinements (`kata/refine`)

- `min_length(schema: Schema(String), n: Int) -> Schema(String)`
- `max_length(schema: Schema(String), n: Int) -> Schema(String)`
- `matches(schema: Schema(String), pattern: String) -> Schema(String)`
- `email(schema: Schema(String)) -> Schema(String)`
- `min(schema: Schema(Int), n: Int) -> Schema(Int)`
- `max(schema: Schema(Int), n: Int) -> Schema(Int)`
- `float_min(schema: Schema(Float), n: Float) -> Schema(Float)`
- `float_max(schema: Schema(Float), n: Float) -> Schema(Float)`

### Coercion (`kata/coerce`)

- `int() -> Schema(Int)`
- `float() -> Schema(Float)`
- `bool() -> Schema(Bool)`

### Format (`kata/format`)

- `decode(schema: Schema(a), fmt: Format(raw), input: raw) -> Result(a, DecodeError)`
- `encode(schema: Schema(a), fmt: Format(raw), value: a) -> Result(raw, String)`

### JSON (`kata_json`)

- `format() -> Format(String)`
- `parse(json: String) -> Result(Value, String)`
- `serialize(value: Value) -> String`
- `decode_json(schema: Schema(a), json: String) -> Result(a, JsonError)`
- `encode_json(schema: Schema(a), value: a) -> String`

### Error Utilities (`kata/error`)

- `prepend_path(errors: List(Error), segment: PathSegment) -> List(Error)`
- `path_to_string(path: List(PathSegment)) -> String`
- `format_error(error: Error) -> String`
- `format_errors(errors: List(Error)) -> String`

### JSON Schema (`kata/json_schema`)

- `to_json_schema(schema: Schema(a)) -> String`
- `ast_to_json_string(ast: Ast) -> String`

### Dynamic Interop (`kata/dynamic`)

- `from_dynamic(dyn: Dynamic) -> Result(Value, String)`
- `to_dynamic(value: Value) -> Dynamic`
