import gleeunit/should
import kata/format.{ParseError, SchemaError}
import kata/schema
import kata_json

pub type User {
  User(name: String, age: Int)
}

fn user_schema() -> schema.Schema(User) {
  use name <- schema.field("name", schema.string(), fn(u: User) { u.name })
  use age <- schema.field("age", schema.int(), fn(u: User) { u.age })
  schema.done(User(name:, age:))
}

// --- decode: parse failure ---

pub fn decode_parse_error_test() {
  format.decode(schema.string(), kata_json.format(), "{bad")
  |> should.be_error()
  |> should_be_parse_error()
}

// --- decode: schema failure ---

pub fn decode_schema_error_test() {
  // Valid JSON but wrong type: pass an int where string is expected
  format.decode(schema.string(), kata_json.format(), "42")
  |> should.be_error()
  |> should_be_schema_error()
}

pub fn decode_schema_missing_field_test() {
  format.decode(user_schema(), kata_json.format(), "{\"name\": \"Alice\"}")
  |> should.be_error()
  |> should_be_schema_error()
}

// --- decode: success ---

pub fn decode_string_test() {
  format.decode(schema.string(), kata_json.format(), "\"hello\"")
  |> should.equal(Ok("hello"))
}

pub fn decode_int_test() {
  format.decode(schema.int(), kata_json.format(), "42")
  |> should.equal(Ok(42))
}

pub fn decode_object_test() {
  format.decode(user_schema(), kata_json.format(), "{\"name\": \"Alice\", \"age\": 30}")
  |> should.equal(Ok(User("Alice", 30)))
}

// --- encode ---

pub fn encode_string_test() {
  format.encode(schema.string(), kata_json.format(), "hello")
  |> should.equal(Ok("\"hello\""))
}

pub fn encode_int_test() {
  format.encode(schema.int(), kata_json.format(), 42)
  |> should.equal(Ok("42"))
}

// --- roundtrip ---

pub fn roundtrip_primitive_test() {
  let assert Ok(json) = format.encode(schema.string(), kata_json.format(), "hello")
  format.decode(schema.string(), kata_json.format(), json)
  |> should.equal(Ok("hello"))
}

pub fn roundtrip_object_test() {
  let user = User("Alice", 30)
  let assert Ok(json) = format.encode(user_schema(), kata_json.format(), user)
  format.decode(user_schema(), kata_json.format(), json)
  |> should.equal(Ok(user))
}

// --- helpers ---

fn should_be_parse_error(err: format.DecodeError) -> Nil {
  case err {
    ParseError(_) -> Nil
    SchemaError(_) -> should.fail()
  }
}

fn should_be_schema_error(err: format.DecodeError) -> Nil {
  case err {
    SchemaError(_) -> Nil
    ParseError(_) -> should.fail()
  }
}
