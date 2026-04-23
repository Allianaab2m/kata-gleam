import gleeunit/should
import kata
import kata/value.{VInt}

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

pub fn transform_decode_success_test() {
  percent_schema()
  |> kata.decode(VInt(50))
  |> should.equal(Ok(Percent(50)))
}

pub fn transform_decode_failure_test() {
  percent_schema()
  |> kata.decode(VInt(150))
  |> should.be_error()
}

pub fn transform_encode_test() {
  percent_schema()
  |> kata.encode(Percent(75))
  |> should.equal(VInt(75))
}

pub fn transform_roundtrip_test() {
  let p = Percent(42)
  let encoded = kata.encode(percent_schema(), p)
  let assert Ok(decoded) = kata.decode(percent_schema(), encoded)
  decoded |> should.equal(p)
}
