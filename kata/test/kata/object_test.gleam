import gleeunit/should
import kata
import kata/value.{VInt, VNull, VObject, VString}

pub type User {
  User(name: String, age: Int)
}

fn user_schema() {
  use name <- kata.field("name", kata.string(), fn(u: User) { u.name })
  use age <- kata.field("age", kata.int(), fn(u: User) { u.age })
  kata.done(User(name:, age:))
}

pub fn user_decode_test() {
  let value = VObject([#("name", VString("Alice")), #("age", VInt(30))])
  user_schema()
  |> kata.decode(value)
  |> should.equal(Ok(User("Alice", 30)))
}

pub fn user_encode_test() {
  let user = User("Alice", 30)
  user_schema()
  |> kata.encode(user)
  |> should.equal(VObject([#("name", VString("Alice")), #("age", VInt(30))]))
}

pub fn user_missing_field_test() {
  let value = VObject([#("name", VString("Alice"))])
  user_schema()
  |> kata.decode(value)
  |> should.be_error()
}

pub fn user_wrong_type_test() {
  let value =
    VObject([#("name", VString("Alice")), #("age", VString("thirty"))])
  user_schema()
  |> kata.decode(value)
  |> should.be_error()
}

pub fn user_not_object_test() {
  user_schema()
  |> kata.decode(VString("not an object"))
  |> should.be_error()
}

// Nested object

pub type Profile {
  Profile(user: User, bio: String)
}

fn profile_schema() {
  use user <- kata.field("user", user_schema(), fn(p: Profile) { p.user })
  use bio <- kata.field("bio", kata.string(), fn(p: Profile) { p.bio })
  kata.done(Profile(user:, bio:))
}

pub fn nested_object_decode_test() {
  let value =
    VObject([
      #("user", VObject([#("name", VString("Bob")), #("age", VInt(25))])),
      #("bio", VString("hello")),
    ])
  profile_schema()
  |> kata.decode(value)
  |> should.equal(Ok(Profile(User("Bob", 25), "hello")))
}

pub fn nested_object_encode_test() {
  let profile = Profile(User("Bob", 25), "hello")
  profile_schema()
  |> kata.encode(profile)
  |> should.equal(
    VObject([
      #("user", VObject([#("name", VString("Bob")), #("age", VInt(25))])),
      #("bio", VString("hello")),
    ]),
  )
}

// Optional field

pub type Config {
  Config(host: String, port: Int)
}

fn config_schema() {
  use host <- kata.field("host", kata.string(), fn(c: Config) { c.host })
  use port <- kata.optional_field("port", kata.int(), 8080, fn(c: Config) {
    c.port
  })
  kata.done(Config(host:, port:))
}

pub fn optional_field_present_test() {
  let value = VObject([#("host", VString("localhost")), #("port", VInt(3000))])
  config_schema()
  |> kata.decode(value)
  |> should.equal(Ok(Config("localhost", 3000)))
}

pub fn optional_field_missing_test() {
  let value = VObject([#("host", VString("localhost"))])
  config_schema()
  |> kata.decode(value)
  |> should.equal(Ok(Config("localhost", 8080)))
}

pub fn optional_field_null_test() {
  let value = VObject([#("host", VString("localhost")), #("port", VNull)])
  config_schema()
  |> kata.decode(value)
  |> should.equal(Ok(Config("localhost", 8080)))
}
