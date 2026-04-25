import gleeunit/should
import kata
import kata/coerce
import kata/value.{VBool, VFloat, VInt, VNull, VString}

// --- coerce.int() ---

pub fn coerce_int_from_int_test() {
  coerce.int()
  |> kata.decode(VInt(42))
  |> should.equal(Ok(42))
}

pub fn coerce_int_from_string_test() {
  coerce.int()
  |> kata.decode(VString("42"))
  |> should.equal(Ok(42))
}

pub fn coerce_int_from_negative_string_test() {
  coerce.int()
  |> kata.decode(VString("-7"))
  |> should.equal(Ok(-7))
}

pub fn coerce_int_from_unparseable_string_test() {
  coerce.int()
  |> kata.decode(VString("abc"))
  |> should.be_error()
}

pub fn coerce_int_from_float_string_test() {
  coerce.int()
  |> kata.decode(VString("3.14"))
  |> should.be_error()
}

pub fn coerce_int_type_mismatch_test() {
  coerce.int()
  |> kata.decode(VBool(True))
  |> should.be_error()
}

pub fn coerce_int_null_test() {
  coerce.int()
  |> kata.decode(VNull)
  |> should.be_error()
}

pub fn coerce_int_encode_test() {
  coerce.int()
  |> kata.encode(42)
  |> should.equal(VInt(42))
}

// --- coerce.float() ---

pub fn coerce_float_from_float_test() {
  coerce.float()
  |> kata.decode(VFloat(3.14))
  |> should.equal(Ok(3.14))
}

pub fn coerce_float_from_int_test() {
  coerce.float()
  |> kata.decode(VInt(1))
  |> should.equal(Ok(1.0))
}

pub fn coerce_float_from_string_test() {
  coerce.float()
  |> kata.decode(VString("3.14"))
  |> should.equal(Ok(3.14))
}

pub fn coerce_float_from_unparseable_string_test() {
  coerce.float()
  |> kata.decode(VString("abc"))
  |> should.be_error()
}

pub fn coerce_float_type_mismatch_test() {
  coerce.float()
  |> kata.decode(VBool(True))
  |> should.be_error()
}

pub fn coerce_float_null_test() {
  coerce.float()
  |> kata.decode(VNull)
  |> should.be_error()
}

pub fn coerce_float_encode_test() {
  coerce.float()
  |> kata.encode(3.14)
  |> should.equal(VFloat(3.14))
}

// --- coerce.bool() ---

pub fn coerce_bool_from_bool_test() {
  coerce.bool()
  |> kata.decode(VBool(True))
  |> should.equal(Ok(True))
}

pub fn coerce_bool_from_string_true_test() {
  coerce.bool()
  |> kata.decode(VString("true"))
  |> should.equal(Ok(True))
}

pub fn coerce_bool_from_string_false_test() {
  coerce.bool()
  |> kata.decode(VString("false"))
  |> should.equal(Ok(False))
}

pub fn coerce_bool_from_invalid_string_test() {
  coerce.bool()
  |> kata.decode(VString("yes"))
  |> should.be_error()
}

pub fn coerce_bool_from_empty_string_test() {
  coerce.bool()
  |> kata.decode(VString(""))
  |> should.be_error()
}

pub fn coerce_bool_type_mismatch_test() {
  coerce.bool()
  |> kata.decode(VInt(1))
  |> should.be_error()
}

pub fn coerce_bool_null_test() {
  coerce.bool()
  |> kata.decode(VNull)
  |> should.be_error()
}

pub fn coerce_bool_encode_test() {
  coerce.bool()
  |> kata.encode(False)
  |> should.equal(VBool(False))
}
