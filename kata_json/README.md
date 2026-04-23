# kata_json

**kata_json** — JSON adapter for [kata](../kata).

## Installation

```sh
gleam add kata_json
```

## Quick Start

```gleam
import kata/schema
import kata/refine
import kata_json

pub type User {
  User(name: String, email: String, age: Int)
}

fn user_schema() -> schema.Schema(User) {
  use name <- schema.field("name", schema.string() |> refine.min_length(1), fn(u: User) { u.name })
  use email <- schema.field("email", schema.string(), fn(u: User) { u.email })
  use age <- schema.field("age", schema.int() |> refine.min(0), fn(u: User) { u.age })
  schema.done(User(name:, email:, age:))
}

// Decode from JSON
let assert Ok(user) = kata_json.decode_json(user_schema(), "{\"name\":\"Alice\",\"email\":\"a@b.com\",\"age\":30}")

// Encode to JSON
let json = kata_json.encode_json(user_schema(), User("Alice", "a@b.com", 30))
// -> "{\"name\":\"Alice\",\"email\":\"a@b.com\",\"age\":30}"
```

## API

- `parse(input: String) -> Result(Value, String)` — Parse JSON to Value (schema-independent)
- `serialize(v: Value) -> String` — Serialize Value to JSON string (schema-independent)
- `decode_json(schema, input) -> Result(a, JsonError)` — Decode JSON using a schema
- `encode_json(schema, value) -> String` — Encode a value to JSON using a schema

## Development

```sh
gleam test  # Run the tests
```
