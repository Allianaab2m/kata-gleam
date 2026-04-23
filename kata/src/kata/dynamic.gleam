/// Conversion between gleam/dynamic.Dynamic and kata/value.Value.
/// Enables interop with stdlib's dynamic decode pipeline.
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None}
import kata/value.{
  type Value, VBool, VFloat, VInt, VList, VNull, VObject, VString,
}

/// Convert a Dynamic value to a kata Value.
/// Tries Bool, Int, Float, String, List, Dict in order.
/// Nil/None/null becomes VNull.
pub fn from_dynamic(d: dynamic.Dynamic) -> Result(Value, String) {
  // Try each decoder in order
  case decode.run(d, decode.bool) {
    Ok(b) -> Ok(VBool(b))
    Error(_) ->
      case decode.run(d, decode.int) {
        Ok(n) -> Ok(VInt(n))
        Error(_) ->
          case decode.run(d, decode.float) {
            Ok(f) -> Ok(VFloat(f))
            Error(_) ->
              case decode.run(d, decode.string) {
                Ok(s) -> Ok(VString(s))
                Error(_) ->
                  case decode.run(d, decode.list(decode.dynamic)) {
                    Ok(items) -> {
                      try_decode_list(items, [])
                    }
                    Error(_) ->
                      case
                        decode.run(
                          d,
                          decode.dict(decode.string, decode.dynamic),
                        )
                      {
                        Ok(entries) -> {
                          try_decode_dict(dict.to_list(entries), [])
                        }
                        Error(_) ->
                          // Try optional (nil/null/undefined)
                          case decode.run(d, decode.optional(decode.string)) {
                            Ok(None) -> Ok(VNull)
                            _ ->
                              Error(
                                "unsupported dynamic type: "
                                <> dynamic.classify(d),
                              )
                          }
                      }
                  }
              }
          }
      }
  }
}

fn try_decode_list(
  items: List(dynamic.Dynamic),
  acc: List(Value),
) -> Result(Value, String) {
  case items {
    [] -> Ok(VList(list.reverse(acc)))
    [item, ..rest] -> {
      case from_dynamic(item) {
        Ok(v) -> try_decode_list(rest, [v, ..acc])
        Error(e) -> Error(e)
      }
    }
  }
}

fn try_decode_dict(
  entries: List(#(String, dynamic.Dynamic)),
  acc: List(#(String, Value)),
) -> Result(Value, String) {
  case entries {
    [] -> Ok(VObject(list.reverse(acc)))
    [#(k, v), ..rest] -> {
      case from_dynamic(v) {
        Ok(val) -> try_decode_dict(rest, [#(k, val), ..acc])
        Error(e) -> Error(e)
      }
    }
  }
}

/// Convert a kata Value to a Dynamic value.
pub fn to_dynamic(v: Value) -> dynamic.Dynamic {
  case v {
    VNull -> dynamic.nil()
    VBool(b) -> dynamic.bool(b)
    VInt(n) -> dynamic.int(n)
    VFloat(f) -> dynamic.float(f)
    VString(s) -> dynamic.string(s)
    VList(items) -> dynamic.list(list.map(items, to_dynamic))
    VObject(entries) ->
      dynamic.properties(
        list.map(entries, fn(pair) {
          #(dynamic.string(pair.0), to_dynamic(pair.1))
        }),
      )
  }
}
