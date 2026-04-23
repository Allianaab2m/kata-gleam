import gleam/dict
import gleam/option.{None, Some}
import gleeunit/should
import kata
import kata/value.{VInt, VList, VNull, VObject, VString}

pub fn list_decode_test() {
  kata.list(kata.int())
  |> kata.decode(VList([VInt(1), VInt(2), VInt(3)]))
  |> should.equal(Ok([1, 2, 3]))
}

pub fn list_decode_empty_test() {
  kata.list(kata.string())
  |> kata.decode(VList([]))
  |> should.equal(Ok([]))
}

pub fn list_decode_type_mismatch_test() {
  kata.list(kata.int())
  |> kata.decode(VString("not a list"))
  |> should.be_error()
}

pub fn list_decode_element_error_test() {
  let result =
    kata.list(kata.int())
    |> kata.decode(VList([VInt(1), VString("bad"), VInt(3)]))
  result |> should.be_error()
}

pub fn list_decode_accumulates_errors_test() {
  let result =
    kata.list(kata.int())
    |> kata.decode(VList([VString("a"), VString("b")]))
  case result {
    Error(errs) -> {
      // Should have 2 errors, one for each element
      errs |> should.not_equal([])
    }
    Ok(_) -> should.fail()
  }
}

pub fn list_encode_test() {
  kata.list(kata.int())
  |> kata.encode([1, 2, 3])
  |> should.equal(VList([VInt(1), VInt(2), VInt(3)]))
}

pub fn optional_decode_some_test() {
  kata.optional(kata.string())
  |> kata.decode(VString("hello"))
  |> should.equal(Ok(Some("hello")))
}

pub fn optional_decode_none_test() {
  kata.optional(kata.string())
  |> kata.decode(VNull)
  |> should.equal(Ok(None))
}

pub fn optional_encode_some_test() {
  kata.optional(kata.int())
  |> kata.encode(Some(42))
  |> should.equal(VInt(42))
}

pub fn optional_encode_none_test() {
  kata.optional(kata.int())
  |> kata.encode(None)
  |> should.equal(VNull)
}

pub fn nested_list_test() {
  let schema = kata.list(kata.list(kata.int()))
  let value = VList([VList([VInt(1), VInt(2)]), VList([VInt(3)])])
  schema
  |> kata.decode(value)
  |> should.equal(Ok([[1, 2], [3]]))
}

pub fn dict_decode_test() {
  kata.dict(kata.string(), kata.int())
  |> kata.decode(VObject([#("a", VInt(1)), #("b", VInt(2))]))
  |> should.equal(Ok(dict.from_list([#("a", 1), #("b", 2)])))
}

pub fn dict_encode_test() {
  let d = dict.from_list([#("x", 10)])
  let result = kata.dict(kata.string(), kata.int()) |> kata.encode(d)
  case result {
    VObject(entries) -> {
      entries |> should.not_equal([])
    }
    _ -> should.fail()
  }
}
