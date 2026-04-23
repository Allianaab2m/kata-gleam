import gleam/option.{None, Some}
import gleeunit/should
import kata
import kata/value.{VBool, VFloat, VInt, VList, VNull, VObject, VString}

pub fn encode_string_test() {
  kata.encode(kata.string(), "hello")
  |> should.equal(VString("hello"))
}

pub fn encode_int_test() {
  kata.encode(kata.int(), 42)
  |> should.equal(VInt(42))
}

pub fn encode_float_test() {
  kata.encode(kata.float(), 1.5)
  |> should.equal(VFloat(1.5))
}

pub fn encode_bool_test() {
  kata.encode(kata.bool(), True)
  |> should.equal(VBool(True))
}

pub fn encode_list_test() {
  kata.encode(kata.list(kata.string()), ["a", "b"])
  |> should.equal(VList([VString("a"), VString("b")]))
}

pub fn encode_optional_some_test() {
  kata.encode(kata.optional(kata.int()), Some(42))
  |> should.equal(VInt(42))
}

pub fn encode_optional_none_test() {
  kata.encode(kata.optional(kata.int()), None)
  |> should.equal(VNull)
}

pub type Item {
  Item(name: String, count: Int)
}

pub fn encode_object_test() {
  let schema = {
    use name <- kata.field("name", kata.string(), fn(i: Item) { i.name })
    use count <- kata.field("count", kata.int(), fn(i: Item) { i.count })
    kata.done(Item(name:, count:))
  }
  kata.encode(schema, Item("widget", 5))
  |> should.equal(VObject([#("name", VString("widget")), #("count", VInt(5))]))
}
