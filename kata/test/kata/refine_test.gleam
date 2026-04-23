import gleeunit/should
import kata
import kata/ast.{AstInt, AstString}
import kata/refine
import kata/value.{VInt, VString}

pub fn min_length_pass_test() {
  kata.string()
  |> refine.min_length(3)
  |> kata.decode(VString("hello"))
  |> should.equal(Ok("hello"))
}

pub fn min_length_fail_test() {
  kata.string()
  |> refine.min_length(3)
  |> kata.decode(VString("hi"))
  |> should.be_error()
}

pub fn max_length_pass_test() {
  kata.string()
  |> refine.max_length(5)
  |> kata.decode(VString("hello"))
  |> should.equal(Ok("hello"))
}

pub fn max_length_fail_test() {
  kata.string()
  |> refine.max_length(3)
  |> kata.decode(VString("hello"))
  |> should.be_error()
}

pub fn matches_pass_test() {
  kata.string()
  |> refine.matches("^[a-z]+$")
  |> kata.decode(VString("hello"))
  |> should.equal(Ok("hello"))
}

pub fn matches_fail_test() {
  kata.string()
  |> refine.matches("^[a-z]+$")
  |> kata.decode(VString("Hello123"))
  |> should.be_error()
}

pub fn email_pass_test() {
  kata.string()
  |> refine.email()
  |> kata.decode(VString("test@example.com"))
  |> should.equal(Ok("test@example.com"))
}

pub fn email_fail_test() {
  kata.string()
  |> refine.email()
  |> kata.decode(VString("not-an-email"))
  |> should.be_error()
}

pub fn min_pass_test() {
  kata.int()
  |> refine.min(0)
  |> kata.decode(VInt(5))
  |> should.equal(Ok(5))
}

pub fn min_fail_test() {
  kata.int()
  |> refine.min(0)
  |> kata.decode(VInt(-1))
  |> should.be_error()
}

pub fn max_pass_test() {
  kata.int()
  |> refine.max(100)
  |> kata.decode(VInt(50))
  |> should.equal(Ok(50))
}

pub fn max_fail_test() {
  kata.int()
  |> refine.max(100)
  |> kata.decode(VInt(150))
  |> should.be_error()
}

pub fn refinement_encode_passthrough_test() {
  // Refinements don't affect encode
  kata.string()
  |> refine.min_length(10)
  |> kata.encode("hi")
  |> should.equal(VString("hi"))
}

// AST reflects refinements
pub fn string_refinement_ast_test() {
  let schema =
    kata.string()
    |> refine.min_length(1)
  let ast = kata.to_ast(schema)
  case ast {
    AstString(refs) -> {
      refs |> should.not_equal([])
    }
    _ -> should.fail()
  }
}

pub fn int_refinement_ast_test() {
  let schema =
    kata.int()
    |> refine.min(0)
    |> refine.max(150)
  let ast = kata.to_ast(schema)
  case ast {
    AstInt(refs) -> {
      refs |> should.not_equal([])
    }
    _ -> should.fail()
  }
}
