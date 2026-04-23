import gleeunit/should
import kata
import kata/ast.{
  AstBool, AstBrand, AstFloat, AstInt, AstList, AstObject, AstOption, AstString,
  AstUnion, FieldSpec,
}
import kata/refine

pub type User {
  User(name: String, age: Int)
}

pub fn string_ast_test() {
  kata.to_ast(kata.string())
  |> should.equal(AstString([]))
}

pub fn int_ast_test() {
  kata.to_ast(kata.int())
  |> should.equal(AstInt([]))
}

pub fn float_ast_test() {
  kata.to_ast(kata.float())
  |> should.equal(AstFloat([]))
}

pub fn bool_ast_test() {
  kata.to_ast(kata.bool())
  |> should.equal(AstBool)
}

pub fn list_ast_test() {
  kata.to_ast(kata.list(kata.int()))
  |> should.equal(AstList(AstInt([])))
}

pub fn optional_ast_test() {
  kata.to_ast(kata.optional(kata.string()))
  |> should.equal(AstOption(AstString([])))
}

pub fn object_ast_test() {
  let schema = {
    use name <- kata.field("name", kata.string(), fn(u: User) { u.name })
    use age <- kata.field("age", kata.int(), fn(u: User) { u.age })
    kata.done(User(name:, age:))
  }
  kata.to_ast(schema)
  |> should.equal(
    AstObject([
      FieldSpec("name", AstString([]), False),
      FieldSpec("age", AstInt([]), False),
    ]),
  )
}

pub fn refined_object_ast_test() {
  let schema = {
    use name <- kata.field(
      "name",
      kata.string() |> refine.min_length(1),
      fn(u: User) { u.name },
    )
    use age <- kata.field(
      "age",
      kata.int() |> refine.min(0) |> refine.max(150),
      fn(u: User) { u.age },
    )
    kata.done(User(name:, age:))
  }

  let ast = kata.to_ast(schema)
  case ast {
    AstObject([
      FieldSpec("name", AstString(name_refs), False),
      FieldSpec("age", AstInt(age_refs), False),
    ]) -> {
      name_refs |> should.not_equal([])
      age_refs |> should.not_equal([])
    }
    _ -> should.fail()
  }
}

pub type Shape {
  Circle(radius: Float)
  Rectangle(width: Float, height: Float)
}

pub fn union_ast_test() {
  let schema =
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
  let ast = kata.to_ast(schema)
  case ast {
    AstUnion("kind", [#("circle", _), #("rectangle", _)]) -> Nil
    _ -> should.fail()
  }
}

pub type Email {
  Email(String)
}

pub fn brand_ast_test() {
  let schema =
    kata.string()
    |> kata.brand("Email", Email, fn(e: Email) {
      let Email(s) = e
      s
    })
  let ast = kata.to_ast(schema)
  case ast {
    AstBrand("Email", AstString([])) -> Nil
    _ -> should.fail()
  }
}
