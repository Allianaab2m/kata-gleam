import gleeunit/should
import kata
import kata/value.{VFloat, VObject, VString}

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

pub fn union_decode_circle_test() {
  let value = VObject([#("kind", VString("circle")), #("radius", VFloat(3.14))])
  shape_schema()
  |> kata.decode(value)
  |> should.equal(Ok(Circle(3.14)))
}

pub fn union_decode_rectangle_test() {
  let value =
    VObject([
      #("kind", VString("rectangle")),
      #("width", VFloat(10.0)),
      #("height", VFloat(20.0)),
    ])
  shape_schema()
  |> kata.decode(value)
  |> should.equal(Ok(Rectangle(10.0, 20.0)))
}

pub fn union_encode_circle_test() {
  shape_schema()
  |> kata.encode(Circle(3.14))
  |> should.equal(
    VObject([#("kind", VString("circle")), #("radius", VFloat(3.14))]),
  )
}

pub fn union_encode_rectangle_test() {
  shape_schema()
  |> kata.encode(Rectangle(10.0, 20.0))
  |> should.equal(
    VObject([
      #("kind", VString("rectangle")),
      #("width", VFloat(10.0)),
      #("height", VFloat(20.0)),
    ]),
  )
}

pub fn union_unknown_discriminator_test() {
  let value = VObject([#("kind", VString("triangle")), #("sides", VFloat(3.0))])
  shape_schema()
  |> kata.decode(value)
  |> should.be_error()
}

pub fn union_missing_discriminator_test() {
  let value = VObject([#("radius", VFloat(3.14))])
  shape_schema()
  |> kata.decode(value)
  |> should.be_error()
}
