import gleeunit
import gleeunit/should
import kata/coerce
import kata/refine
import kata/schema
import kata/value.{VObject, VString}
import kata_form

pub fn main() -> Nil {
  gleeunit.main()
}

// --- parse ---

pub fn parse_simple_test() {
  kata_form.parse("name=Alice&age=30")
  |> should.equal(
    Ok(VObject([#("name", VString("Alice")), #("age", VString("30"))])),
  )
}

pub fn parse_url_encoded_test() {
  let result = kata_form.parse("email=a%40b.com")
  case result {
    Ok(VObject([#("email", VString(email))])) ->
      email |> should.equal("a@b.com")
    _ -> should.fail()
  }
}

pub fn parse_empty_test() {
  kata_form.parse("")
  |> should.equal(Ok(VObject([])))
}

// --- decode ---

pub type Login {
  Login(email: String, password: String)
}

fn login_schema() {
  use email <- schema.field("email", schema.string(), fn(l: Login) { l.email })
  use password <- schema.field("password", schema.string(), fn(l: Login) {
    l.password
  })
  schema.done(Login(email:, password:))
}

pub fn decode_login_test() {
  kata_form.decode(login_schema(), "email=alice%40example.com&password=secret")
  |> should.equal(Ok(Login("alice@example.com", "secret")))
}

pub fn decode_missing_field_test() {
  kata_form.decode(login_schema(), "email=alice%40example.com")
  |> should.be_error()
}

// --- coercion ---

pub type Config {
  Config(host: String, port: Int, debug: Bool)
}

fn config_schema() {
  use host <- schema.field("host", schema.string(), fn(c: Config) { c.host })
  use port <- schema.field("port", coerce.int(), fn(c: Config) { c.port })
  use debug <- schema.field("debug", coerce.bool(), fn(c: Config) { c.debug })
  schema.done(Config(host:, port:, debug:))
}

pub fn decode_with_coercion_test() {
  kata_form.decode(config_schema(), "host=localhost&port=3000&debug=true")
  |> should.equal(Ok(Config("localhost", 3000, True)))
}

pub fn decode_invalid_int_test() {
  kata_form.decode(config_schema(), "host=localhost&port=abc&debug=false")
  |> should.be_error()
}

// --- decode_pairs ---

pub fn decode_pairs_test() {
  let pairs = [#("email", "test@test.com"), #("password", "pass123")]
  kata_form.decode_pairs(login_schema(), pairs)
  |> should.equal(Ok(Login("test@test.com", "pass123")))
}

// --- refinement with form ---

pub type Signup {
  Signup(name: String, age: Int)
}

fn signup_schema() {
  use name <- schema.field(
    "name",
    schema.string() |> refine.min_length(1),
    fn(s: Signup) { s.name },
  )
  use age <- schema.field(
    "age",
    coerce.int() |> refine.min(0) |> refine.max(150),
    fn(s: Signup) { s.age },
  )
  schema.done(Signup(name:, age:))
}

pub fn decode_with_refinement_test() {
  kata_form.decode(signup_schema(), "name=Alice&age=30")
  |> should.equal(Ok(Signup("Alice", 30)))
}

pub fn decode_refinement_fail_test() {
  kata_form.decode(signup_schema(), "name=&age=200")
  |> should.be_error()
}
