import gleeunit/should
import kata
import kata/value.{VBool, VFloat, VInt, VNull, VString}

pub fn string_decode_test() {
  kata.string()
  |> kata.decode(VString("hello"))
  |> should.equal(Ok("hello"))
}

pub fn string_decode_type_mismatch_test() {
  kata.string()
  |> kata.decode(VInt(42))
  |> should.be_error()
}

pub fn string_encode_test() {
  kata.string()
  |> kata.encode("hello")
  |> should.equal(VString("hello"))
}

pub fn int_decode_test() {
  kata.int()
  |> kata.decode(VInt(42))
  |> should.equal(Ok(42))
}

pub fn int_decode_type_mismatch_test() {
  kata.int()
  |> kata.decode(VString("42"))
  |> should.be_error()
}

pub fn int_no_coercion_from_float_test() {
  kata.int()
  |> kata.decode(VFloat(1.0))
  |> should.be_error()
}

pub fn int_encode_test() {
  kata.int()
  |> kata.encode(42)
  |> should.equal(VInt(42))
}

pub fn float_decode_test() {
  kata.float()
  |> kata.decode(VFloat(3.14))
  |> should.equal(Ok(3.14))
}

pub fn float_decode_type_mismatch_test() {
  kata.float()
  |> kata.decode(VInt(1))
  |> should.be_error()
}

pub fn float_encode_test() {
  kata.float()
  |> kata.encode(3.14)
  |> should.equal(VFloat(3.14))
}

pub fn bool_decode_test() {
  kata.bool()
  |> kata.decode(VBool(True))
  |> should.equal(Ok(True))
}

pub fn bool_decode_type_mismatch_test() {
  kata.bool()
  |> kata.decode(VNull)
  |> should.be_error()
}

pub fn bool_encode_test() {
  kata.bool()
  |> kata.encode(False)
  |> should.equal(VBool(False))
}
