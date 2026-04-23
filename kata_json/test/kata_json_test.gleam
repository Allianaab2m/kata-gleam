import gleam/string
import gleeunit
import gleeunit/should
import kata/refine
import kata/schema
import kata/value.{VBool, VFloat, VInt, VList, VNull, VObject, VString}
import kata_json

pub fn main() -> Nil {
  gleeunit.main()
}

// --- parse ---

pub fn parse_string_test() {
  kata_json.parse("\"hello\"")
  |> should.equal(Ok(VString("hello")))
}

pub fn parse_int_test() {
  kata_json.parse("42")
  |> should.equal(Ok(VInt(42)))
}

pub fn parse_float_test() {
  kata_json.parse("3.14")
  |> should.equal(Ok(VFloat(3.14)))
}

pub fn parse_bool_test() {
  kata_json.parse("true")
  |> should.equal(Ok(VBool(True)))
}

pub fn parse_null_test() {
  kata_json.parse("null")
  |> should.equal(Ok(VNull))
}

pub fn parse_list_test() {
  kata_json.parse("[1, 2, 3]")
  |> should.equal(Ok(VList([VInt(1), VInt(2), VInt(3)])))
}

pub fn parse_object_test() {
  let result = kata_json.parse("{\"name\": \"Alice\", \"age\": 30}")
  case result {
    Ok(VObject(entries)) -> {
      // Check that entries contain the expected keys
      entries |> should.not_equal([])
    }
    _ -> should.fail()
  }
}

pub fn parse_invalid_json_test() {
  kata_json.parse("{invalid}")
  |> should.be_error()
}

// --- serialize ---

pub fn serialize_string_test() {
  kata_json.serialize(VString("hello"))
  |> should.equal("\"hello\"")
}

pub fn serialize_int_test() {
  kata_json.serialize(VInt(42))
  |> should.equal("42")
}

pub fn serialize_bool_test() {
  kata_json.serialize(VBool(True))
  |> should.equal("true")
}

pub fn serialize_null_test() {
  kata_json.serialize(VNull)
  |> should.equal("null")
}

pub fn serialize_list_test() {
  kata_json.serialize(VList([VInt(1), VInt(2)]))
  |> should.equal("[1,2]")
}

pub fn serialize_object_test() {
  kata_json.serialize(VObject([#("a", VInt(1))]))
  |> should.equal("{\"a\":1}")
}

// --- decode_json / encode_json with schema ---

pub type User {
  User(name: String, email: String, age: Int)
}

fn user_schema() -> schema.Schema(User) {
  use name <- schema.field(
    "name",
    schema.string() |> refine.min_length(1),
    fn(u: User) { u.name },
  )
  use email <- schema.field("email", schema.string(), fn(u: User) { u.email })
  use age <- schema.field(
    "age",
    schema.int() |> refine.min(0) |> refine.max(150),
    fn(u: User) { u.age },
  )
  schema.done(User(name:, email:, age:))
}

pub fn decode_json_user_test() {
  let json = "{\"name\": \"Alice\", \"email\": \"a@b.com\", \"age\": 30}"
  kata_json.decode_json(user_schema(), json)
  |> should.equal(Ok(User("Alice", "a@b.com", 30)))
}

pub fn decode_json_invalid_test() {
  let json = "{\"name\": \"\", \"email\": \"a@b.com\", \"age\": 30}"
  kata_json.decode_json(user_schema(), json)
  |> should.be_error()
}

pub fn decode_json_parse_error_test() {
  kata_json.decode_json(user_schema(), "{bad json}")
  |> should.be_error()
}

pub fn encode_json_user_test() {
  let json = kata_json.encode_json(user_schema(), User("Alice", "a@b.com", 30))
  json |> should_contain("\"name\"")
  json |> should_contain("\"Alice\"")
  json |> should_contain("\"age\"")
  json |> should_contain("30")
}

// --- roundtrip ---

pub fn json_roundtrip_test() {
  let user = User("Alice", "a@b.com", 30)
  let json = kata_json.encode_json(user_schema(), user)
  let assert Ok(decoded) = kata_json.decode_json(user_schema(), json)
  decoded |> should.equal(user)
}

// --- tagged union roundtrip ---

pub type Shape {
  Circle(radius: Float)
  Rectangle(width: Float, height: Float)
}

fn shape_schema() -> schema.Schema(Shape) {
  schema.tagged_union(
    "kind",
    fn(s: Shape) {
      case s {
        Circle(_) -> "circle"
        Rectangle(_, _) -> "rectangle"
      }
    },
    [
      #("circle", {
        use r <- schema.field("radius", schema.float(), fn(s: Shape) {
          case s {
            Circle(r) -> r
            _ -> 0.0
          }
        })
        schema.done(Circle(r))
      }),
      #("rectangle", {
        use w <- schema.field("width", schema.float(), fn(s: Shape) {
          case s {
            Rectangle(w, _) -> w
            _ -> 0.0
          }
        })
        use h <- schema.field("height", schema.float(), fn(s: Shape) {
          case s {
            Rectangle(_, h) -> h
            _ -> 0.0
          }
        })
        schema.done(Rectangle(w, h))
      }),
    ],
  )
}

pub fn json_circle_roundtrip_test() {
  let shape = Circle(3.14)
  let json = kata_json.encode_json(shape_schema(), shape)
  let assert Ok(decoded) = kata_json.decode_json(shape_schema(), json)
  decoded |> should.equal(shape)
}

pub fn json_rectangle_roundtrip_test() {
  let shape = Rectangle(10.0, 20.0)
  let json = kata_json.encode_json(shape_schema(), shape)
  let assert Ok(decoded) = kata_json.decode_json(shape_schema(), json)
  decoded |> should.equal(shape)
}

// --- recursive tree roundtrip ---

pub type Tree {
  Leaf(Int)
  Node(left: Tree, right: Tree)
}

fn tree_schema() -> schema.Schema(Tree) {
  schema.tagged_union(
    "kind",
    fn(t: Tree) {
      case t {
        Leaf(_) -> "leaf"
        Node(_, _) -> "node"
      }
    },
    [
      #("leaf", {
        use v <- schema.field("value", schema.int(), fn(t: Tree) {
          case t {
            Leaf(n) -> n
            _ -> 0
          }
        })
        schema.done(Leaf(v))
      }),
      #("node", {
        use l <- schema.field("left", schema.lazy(tree_schema), fn(t: Tree) {
          case t {
            Node(l, _) -> l
            _ -> Leaf(0)
          }
        })
        use r <- schema.field("right", schema.lazy(tree_schema), fn(t: Tree) {
          case t {
            Node(_, r) -> r
            _ -> Leaf(0)
          }
        })
        schema.done(Node(l, r))
      }),
    ],
  )
}

pub fn json_tree_roundtrip_test() {
  let tree = Node(Node(Leaf(1), Leaf(2)), Node(Leaf(3), Node(Leaf(4), Leaf(5))))
  let json = kata_json.encode_json(tree_schema(), tree)
  let assert Ok(decoded) = kata_json.decode_json(tree_schema(), json)
  decoded |> should.equal(tree)
}

// --- brand roundtrip ---

pub type Email {
  Email(String)
}

fn email_schema() -> schema.Schema(Email) {
  schema.string()
  |> refine.email()
  |> schema.brand("Email", Email, fn(e: Email) {
    let Email(s) = e
    s
  })
}

pub fn json_brand_roundtrip_test() {
  let email = Email("test@example.com")
  let json = kata_json.encode_json(email_schema(), email)
  let assert Ok(decoded) = kata_json.decode_json(email_schema(), json)
  decoded |> should.equal(email)
}

fn should_contain(json: String, substring: String) -> Nil {
  string.contains(json, substring)
  |> should.equal(True)
}
