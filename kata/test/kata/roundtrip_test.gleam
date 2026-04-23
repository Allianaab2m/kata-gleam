import gleam/option.{None, Some}
import gleeunit/should
import kata
import kata/refine

// --- Primitives ---

pub fn string_roundtrip_test() {
  let v = "hello"
  let schema = kata.string()
  let assert Ok(decoded) = kata.decode(schema, kata.encode(schema, v))
  decoded |> should.equal(v)
}

pub fn int_roundtrip_test() {
  let v = 42
  let schema = kata.int()
  let assert Ok(decoded) = kata.decode(schema, kata.encode(schema, v))
  decoded |> should.equal(v)
}

pub fn float_roundtrip_test() {
  let v = 3.14
  let schema = kata.float()
  let assert Ok(decoded) = kata.decode(schema, kata.encode(schema, v))
  decoded |> should.equal(v)
}

pub fn bool_roundtrip_test() {
  let v = True
  let schema = kata.bool()
  let assert Ok(decoded) = kata.decode(schema, kata.encode(schema, v))
  decoded |> should.equal(v)
}

// --- Containers ---

pub fn list_roundtrip_test() {
  let v = [1, 2, 3]
  let schema = kata.list(kata.int())
  let assert Ok(decoded) = kata.decode(schema, kata.encode(schema, v))
  decoded |> should.equal(v)
}

pub fn optional_some_roundtrip_test() {
  let v = Some("hello")
  let schema = kata.optional(kata.string())
  let assert Ok(decoded) = kata.decode(schema, kata.encode(schema, v))
  decoded |> should.equal(v)
}

pub fn optional_none_roundtrip_test() {
  let v = None
  let schema = kata.optional(kata.int())
  let assert Ok(decoded) = kata.decode(schema, kata.encode(schema, v))
  decoded |> should.equal(v)
}

// --- Object ---

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

pub fn user_roundtrip_test() {
  let user = User("Alice", "a@b.com", 30)
  let encoded = kata.encode(user_schema(), user)
  let assert Ok(decoded) = kata.decode(user_schema(), encoded)
  decoded |> should.equal(user)
}

// --- Union ---

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

pub fn circle_roundtrip_test() {
  let v = Circle(3.14)
  let encoded = kata.encode(shape_schema(), v)
  let assert Ok(decoded) = kata.decode(shape_schema(), encoded)
  decoded |> should.equal(v)
}

pub fn rectangle_roundtrip_test() {
  let v = Rectangle(10.0, 20.0)
  let encoded = kata.encode(shape_schema(), v)
  let assert Ok(decoded) = kata.decode(shape_schema(), encoded)
  decoded |> should.equal(v)
}

// --- Recursive ---

pub type Tree {
  Leaf(Int)
  Node(left: Tree, right: Tree)
}

fn tree_schema() -> kata.Schema(Tree) {
  kata.tagged_union(
    "kind",
    fn(t: Tree) {
      case t {
        Leaf(_) -> "leaf"
        Node(_, _) -> "node"
      }
    },
    [
      #("leaf", {
        use v <- kata.field("value", kata.int(), fn(t: Tree) {
          case t {
            Leaf(n) -> n
            _ -> 0
          }
        })
        kata.done(Leaf(v))
      }),
      #("node", {
        use l <- kata.field("left", kata.lazy(tree_schema), fn(t: Tree) {
          case t {
            Node(l, _) -> l
            _ -> Leaf(0)
          }
        })
        use r <- kata.field("right", kata.lazy(tree_schema), fn(t: Tree) {
          case t {
            Node(_, r) -> r
            _ -> Leaf(0)
          }
        })
        kata.done(Node(l, r))
      }),
    ],
  )
}

pub fn tree_roundtrip_test() {
  let tree = Node(Node(Leaf(1), Leaf(2)), Node(Leaf(3), Node(Leaf(4), Leaf(5))))
  let encoded = kata.encode(tree_schema(), tree)
  let assert Ok(decoded) = kata.decode(tree_schema(), encoded)
  decoded |> should.equal(tree)
}

// --- Brand ---

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

pub fn brand_roundtrip_test() {
  let v = Email("test@example.com")
  let encoded = kata.encode(email_schema(), v)
  let assert Ok(decoded) = kata.decode(email_schema(), encoded)
  decoded |> should.equal(v)
}

// --- Transform ---

pub type Percent {
  Percent(Int)
}

fn percent_schema() -> kata.Schema(Percent) {
  kata.int()
  |> kata.transform(
    "Percent",
    fn(n) {
      case n >= 0 && n <= 100 {
        True -> Ok(Percent(n))
        False -> Error("must be 0-100")
      }
    },
    fn(p) {
      let Percent(n) = p
      n
    },
    fn() { Percent(0) },
  )
}

pub fn transform_roundtrip_test() {
  let v = Percent(75)
  let encoded = kata.encode(percent_schema(), v)
  let assert Ok(decoded) = kata.decode(percent_schema(), encoded)
  decoded |> should.equal(v)
}
