/// Public AST type for schema introspection.
/// Used by to_json_schema and future ecosystem packages.
import gleam/option.{type Option}

pub type Ast {
  AstString(refinements: List(StringRef))
  AstInt(refinements: List(IntRef))
  AstFloat(refinements: List(FloatRef))
  AstBool
  AstNull
  AstList(item: Ast)
  AstDict(key: Ast, value: Ast)
  AstOption(inner: Ast)
  AstObject(fields: List(FieldSpec))
  AstUnion(discriminator: String, variants: List(#(String, Ast)))
  AstLazy(fn() -> Ast)
  /// Wraps a transformed schema, preserving the base AST
  AstTransformed(name: Option(String), base: Ast)
  /// Nominal typing wrapper
  AstBrand(name: String, base: Ast)
}

pub type FieldSpec {
  FieldSpec(key: String, ast: Ast, optional: Bool)
}

pub type StringRef {
  MinLength(Int)
  MaxLength(Int)
  Pattern(String)
}

pub type IntRef {
  IntMin(Int)
  IntMax(Int)
}

pub type FloatRef {
  FloatMin(Float)
  FloatMax(Float)
}
