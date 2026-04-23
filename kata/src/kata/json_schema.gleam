/// Generate JSON Schema Draft 7 from kata AST.
/// Pure string-based JSON generation (no JSON library dependency).
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import kata/ast.{
  type Ast, type FieldSpec, type FloatRef, type IntRef, type StringRef, AstBool,
  AstBrand, AstDict, AstFloat, AstInt, AstLazy, AstList, AstNull, AstObject,
  AstOption, AstString, AstTransformed, AstUnion, FloatMax, FloatMin, IntMax,
  IntMin, MaxLength, MinLength, Pattern,
}
import kata/schema.{type Schema}

/// Convert a Schema to a JSON Schema Draft 7 string
pub fn to_json_schema(schema: Schema(a)) -> String {
  ast_to_json_string(schema.to_ast(schema))
}

/// Convert an AST node to a JSON Schema string
pub fn ast_to_json_string(node: Ast) -> String {
  render_node(node)
}

fn render_node(node: Ast) -> String {
  case node {
    AstString(refs) -> render_string_schema(refs)
    AstInt(refs) -> render_int_schema(refs)
    AstFloat(refs) -> render_float_schema(refs)
    AstBool -> json_object([#("type", json_string("boolean"))])
    AstNull -> json_object([#("type", json_string("null"))])
    AstList(item) ->
      json_object([
        #("type", json_string("array")),
        #("items", render_node(item)),
      ])
    AstDict(_key, val) ->
      json_object([
        #("type", json_string("object")),
        #("additionalProperties", render_node(val)),
      ])
    AstOption(inner) ->
      json_object([
        #(
          "oneOf",
          json_array([
            render_node(inner),
            json_object([#("type", json_string("null"))]),
          ]),
        ),
      ])
    AstObject(fields) -> render_object_schema(fields)
    AstUnion(_discriminator, variants) -> render_union_schema(variants)
    AstLazy(f) -> render_node(f())
    AstTransformed(_name, base) -> render_node(base)
    AstBrand(name, base) -> render_brand_schema(name, base)
  }
}

fn render_string_schema(refs: List(StringRef)) -> String {
  let base = [#("type", json_string("string"))]
  let extras =
    list.flat_map(refs, fn(r) {
      case r {
        MinLength(n) -> [#("minLength", int.to_string(n))]
        MaxLength(n) -> [#("maxLength", int.to_string(n))]
        Pattern(p) -> [#("pattern", json_string(p))]
      }
    })
  json_object(list.append(base, extras))
}

fn render_int_schema(refs: List(IntRef)) -> String {
  let base = [#("type", json_string("integer"))]
  let extras =
    list.flat_map(refs, fn(r) {
      case r {
        IntMin(n) -> [#("minimum", int.to_string(n))]
        IntMax(n) -> [#("maximum", int.to_string(n))]
      }
    })
  json_object(list.append(base, extras))
}

fn render_float_schema(refs: List(FloatRef)) -> String {
  let base = [#("type", json_string("number"))]
  let extras =
    list.flat_map(refs, fn(r) {
      case r {
        FloatMin(n) -> [#("minimum", float.to_string(n))]
        FloatMax(n) -> [#("maximum", float.to_string(n))]
      }
    })
  json_object(list.append(base, extras))
}

fn render_object_schema(fields: List(FieldSpec)) -> String {
  let props =
    list.map(fields, fn(f: FieldSpec) { #(f.key, render_node(f.ast)) })
  let required =
    fields
    |> list.filter(fn(f: FieldSpec) { !f.optional })
    |> list.map(fn(f: FieldSpec) { json_string(f.key) })

  let base = [
    #("type", json_string("object")),
    #("properties", json_object(props)),
  ]

  let with_required = case required {
    [] -> base
    _ -> list.append(base, [#("required", json_array(required))])
  }

  json_object(with_required)
}

fn render_union_schema(variants: List(#(String, Ast))) -> String {
  let schemas = list.map(variants, fn(pair) { render_node(pair.1) })
  json_object([#("oneOf", json_array(schemas))])
}

fn render_brand_schema(name: String, base: Ast) -> String {
  let rendered = render_node(base)
  inject_title(rendered, name)
}

fn inject_title(json: String, title: String) -> String {
  case string.pop_grapheme(json) {
    Ok(#("{", rest)) -> {
      case string.length(rest) > 0 {
        True -> "{" <> "\"title\":" <> json_string(title) <> "," <> rest
        False -> "{" <> "\"title\":" <> json_string(title) <> "}"
      }
    }
    _ -> json
  }
}

// --- JSON string builders ---

fn json_string(s: String) -> String {
  "\"" <> escape_json_string(s) <> "\""
}

fn escape_json_string(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
}

fn json_object(pairs: List(#(String, String))) -> String {
  let entries =
    list.map(pairs, fn(pair) { json_string(pair.0) <> ":" <> pair.1 })
  "{" <> string.join(entries, ",") <> "}"
}

fn json_array(items: List(String)) -> String {
  "[" <> string.join(items, ",") <> "]"
}
