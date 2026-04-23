import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Error {
  Error(path: List(PathSegment), issue: Issue, schema_name: Option(String))
}

pub type PathSegment {
  Key(String)
  Index(Int)
  Variant(String)
}

pub type Issue {
  /// Type mismatch
  TypeMismatch(expected: String, got: String)
  /// Required field missing
  MissingField(name: String)
  /// Refinement check failed
  RefinementFailed(name: String, message: String)
  /// No variant matched in tagged union
  UnionNoMatch(discriminator: String, tried: List(String), got: String)
  /// Custom error
  Custom(message: String)
}

/// Prepend a path segment to all errors
pub fn prepend_path(errors: List(Error), segment: PathSegment) -> List(Error) {
  list.map(errors, fn(e) { Error(..e, path: [segment, ..e.path]) })
}

/// Format a path as a human-readable string (e.g. "$.user.age")
pub fn path_to_string(path: List(PathSegment)) -> String {
  "$" <> string.join(list.map(path, segment_to_string), "")
}

fn segment_to_string(seg: PathSegment) -> String {
  case seg {
    Key(k) -> "." <> k
    Index(i) -> "[" <> int.to_string(i) <> "]"
    Variant(v) -> "<" <> v <> ">"
  }
}

/// Format a single error as a human-readable string
pub fn format_error(e: Error) -> String {
  let path_str = path_to_string(e.path)
  let issue_str = format_issue(e.issue)
  let name_str = case e.schema_name {
    Some(n) -> " (" <> n <> ")"
    None -> ""
  }
  path_str <> ": " <> issue_str <> name_str
}

/// Format multiple errors
pub fn format_errors(errors: List(Error)) -> String {
  errors
  |> list.map(format_error)
  |> string.join("\n")
}

fn format_issue(issue: Issue) -> String {
  case issue {
    TypeMismatch(expected:, got:) -> "expected " <> expected <> ", got " <> got
    MissingField(name:) -> "missing required field \"" <> name <> "\""
    RefinementFailed(name:, message:) -> name <> ": " <> message
    UnionNoMatch(discriminator:, tried:, got:) ->
      "no variant matched for "
      <> discriminator
      <> "=\""
      <> got
      <> "\" (tried: "
      <> string.join(tried, ", ")
      <> ")"
    Custom(message:) -> message
  }
}
