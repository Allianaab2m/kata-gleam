# kata

**kata** — A bidirectional schema library for Gleam. Define your data shape once, decode and encode with the same definition.

The name comes from the Japanese word "型" (kata), meaning "form" or "mold" — defining the correct shape for your data.

## Installation

```sh
gleam add kata
```

## Quick Start

```gleam
import kata
import kata/refine

pub type User {
  User(name: String, email: String, age: Int)
}

pub fn user_schema() -> kata.Schema(User) {
  use name <- kata.field(
    "name",
    kata.string() |> refine.min_length(1),
    fn(u: User) { u.name },
  )
  use email <- kata.field("email", kata.string(), fn(u: User) { u.email })
  use age <- kata.field(
    "age",
    kata.int() |> refine.min(0) |> refine.max(150),
    fn(u: User) { u.age },
  )
  kata.done(User(name:, email:, age:))
}

// Decode
let value = kata.decode(user_schema(), some_value)

// Encode
let encoded = kata.encode(user_schema(), User("Alice", "a@b.com", 30))
```

## Features

- **Bidirectional**: Decode and encode with a single schema definition
- **AST is public**: Introspect schemas at runtime, generate JSON Schema
- **Minimal dependencies**: Only `gleam_stdlib` and `gleam_regexp`
- **Nominal typing**: `brand` helper for opaque type wrappers
- **Discriminated unions**: `tagged_union` for sum types
- **Recursive schemas**: `lazy` combinator for tree-like structures
- **Refinements**: `min_length`, `max_length`, `matches`, `min`, `max`, etc.
- **JSON Schema**: Generate JSON Schema Draft 7 from any schema's AST

## JSON Support

For JSON encoding/decoding, use the companion package [kata_json](../kata_json):

```sh
gleam add kata_json
```

## v0.1 Scope

This is the initial release. It includes:

- Primitive schemas: `string`, `int`, `float`, `bool`
- Container schemas: `list`, `optional`, `dict`
- Record builder: `field`, `optional_field`, `done`
- Tagged unions, recursive schemas, transform, brand
- Refinements and JSON Schema generation

### Roadmap

- v0.2: JavaScript target, full error accumulation, `kata_form`
- v0.3: `kata_wisp`, `kata_openapi`
- v0.4: `kata_sql`

## Relation to Other Libraries

kata fills a different niche than existing Gleam schema libraries:

- **json_blueprint** / **glon**: Focus on JSON decoding only
- **sift**: Validation library without encode support
- **kata**: Bidirectional (decode + encode) with public AST for ecosystem integration

## Development

```sh
gleam test  # Run the tests
```
