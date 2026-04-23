import gleam/string
import gleeunit/should
import kata
import kata/json_schema
import kata/refine

pub type User {
  User(name: String, email: String, age: Int)
}

fn user_schema() -> kata.Schema(User) {
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

pub fn user_json_schema_has_type_object_test() {
  let schema_json = json_schema.to_json_schema(user_schema())
  schema_json |> should_contain("\"type\":\"object\"")
}

pub fn user_json_schema_has_properties_test() {
  let schema_json = json_schema.to_json_schema(user_schema())
  schema_json |> should_contain("\"properties\"")
}

pub fn user_json_schema_name_is_string_test() {
  let schema_json = json_schema.to_json_schema(user_schema())
  schema_json |> should_contain("\"name\"")
  schema_json |> should_contain("\"string\"")
}

pub fn user_json_schema_has_min_length_test() {
  let schema_json = json_schema.to_json_schema(user_schema())
  schema_json |> should_contain("\"minLength\"")
}

pub fn user_json_schema_age_has_minimum_test() {
  let schema_json = json_schema.to_json_schema(user_schema())
  schema_json |> should_contain("\"minimum\"")
}

pub fn user_json_schema_age_has_maximum_test() {
  let schema_json = json_schema.to_json_schema(user_schema())
  schema_json |> should_contain("\"maximum\"")
}

pub fn user_json_schema_has_required_test() {
  let schema_json = json_schema.to_json_schema(user_schema())
  schema_json |> should_contain("\"required\"")
}

pub fn user_json_schema_has_integer_type_test() {
  let schema_json = json_schema.to_json_schema(user_schema())
  schema_json |> should_contain("\"integer\"")
}

pub type Shape {
  Circle(radius: Float)
  Rectangle(width: Float, height: Float)
}

fn shape_schema() -> kata.Schema(Shape) {
  kata.tagged_union(
    "kind",
    fn(s: Shape) {
      case s {
        Circle(_) -> "circle"
        Rectangle(_, _) -> "rectangle"
      }
    },
    [
      #("circle", {
        use r <- kata.field("radius", kata.float(), fn(s: Shape) {
          case s {
            Circle(r) -> r
            _ -> 0.0
          }
        })
        kata.done(Circle(r))
      }),
      #("rectangle", {
        use w <- kata.field("width", kata.float(), fn(s: Shape) {
          case s {
            Rectangle(w, _) -> w
            _ -> 0.0
          }
        })
        use h <- kata.field("height", kata.float(), fn(s: Shape) {
          case s {
            Rectangle(_, h) -> h
            _ -> 0.0
          }
        })
        kata.done(Rectangle(w, h))
      }),
    ],
  )
}

pub fn union_json_schema_has_one_of_test() {
  let schema_json = json_schema.to_json_schema(shape_schema())
  schema_json |> should_contain("\"oneOf\"")
}

pub type Email {
  Email(String)
}

pub fn brand_json_schema_has_title_test() {
  let schema =
    kata.string()
    |> kata.brand("Email", Email, fn(e: Email) {
      let Email(s) = e
      s
    })
  let schema_json = json_schema.to_json_schema(schema)
  schema_json |> should_contain("\"title\"")
  schema_json |> should_contain("\"Email\"")
}

fn should_contain(json: String, substring: String) -> Nil {
  string.contains(json, substring)
  |> should.equal(True)
}
