/// Intermediate representation used as the hub for decode/encode.
/// Format-agnostic: JSON, form data, etc. all convert to/from Value.
pub type Value {
  VNull
  VBool(Bool)
  VInt(Int)
  VFloat(Float)
  VString(String)
  VList(List(Value))
  /// Key-value pairs with preserved insertion order.
  /// Duplicate keys: first occurrence wins on decode.
  VObject(List(#(String, Value)))
}

/// Convert a Value to a human-readable type name (for error messages).
pub fn classify(v: Value) -> String {
  case v {
    VNull -> "null"
    VBool(_) -> "bool"
    VInt(_) -> "int"
    VFloat(_) -> "float"
    VString(_) -> "string"
    VList(_) -> "list"
    VObject(_) -> "object"
  }
}
