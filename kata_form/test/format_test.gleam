import gleeunit/should
import kata/coerce
import kata/format
import kata/schema
import kata_form

pub type Login {
  Login(email: String, remember: Bool)
}

fn login_schema() {
  use email <- schema.field("email", schema.string(), fn(l: Login) { l.email })
  use remember <- schema.field("remember", coerce.bool(), fn(l: Login) {
    l.remember
  })
  schema.done(Login(email:, remember:))
}

// --- format.decode ---

pub fn format_decode_test() {
  format.decode(
    login_schema(),
    kata_form.format(),
    "email=a%40b.com&remember=true",
  )
  |> should.equal(Ok(Login("a@b.com", True)))
}

pub fn format_decode_missing_field_test() {
  format.decode(login_schema(), kata_form.format(), "email=a%40b.com")
  |> should.be_error()
}

pub fn format_decode_parse_error_test() {
  format.decode(schema.string(), kata_form.format(), "%ZZ")
  |> should.be_error()
}

// --- format.encode ---

pub fn format_encode_test() {
  let login = Login("a@b.com", True)
  let assert Ok(body) =
    format.encode(login_schema(), kata_form.format(), login)
  // Re-decode to verify (URL encoding may vary)
  format.decode(login_schema(), kata_form.format(), body)
  |> should.equal(Ok(login))
}

// --- roundtrip ---

pub fn roundtrip_test() {
  let login = Login("user@example.com", False)
  let assert Ok(body) =
    format.encode(login_schema(), kata_form.format(), login)
  format.decode(login_schema(), kata_form.format(), body)
  |> should.equal(Ok(login))
}
