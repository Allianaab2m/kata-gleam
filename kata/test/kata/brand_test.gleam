import gleeunit/should
import kata
import kata/ast.{AstBrand, AstString}
import kata/refine
import kata/value.{VString}

pub type Email {
  Email(String)
}

fn email_value(e: Email) -> String {
  let Email(s) = e
  s
}

fn email_schema() -> kata.Schema(Email) {
  kata.string()
  |> refine.email()
  |> kata.brand("Email", Email, email_value)
}

pub fn brand_decode_test() {
  email_schema()
  |> kata.decode(VString("test@example.com"))
  |> should.equal(Ok(Email("test@example.com")))
}

pub fn brand_decode_invalid_test() {
  email_schema()
  |> kata.decode(VString("not-an-email"))
  |> should.be_error()
}

pub fn brand_encode_test() {
  email_schema()
  |> kata.encode(Email("test@example.com"))
  |> should.equal(VString("test@example.com"))
}

pub fn brand_roundtrip_test() {
  let email = Email("test@example.com")
  let encoded = kata.encode(email_schema(), email)
  let assert Ok(decoded) = kata.decode(email_schema(), encoded)
  decoded |> should.equal(email)
}

pub fn brand_ast_test() {
  let ast = kata.to_ast(email_schema())
  case ast {
    AstBrand("Email", AstString(_)) -> Nil
    _ -> should.fail()
  }
}
