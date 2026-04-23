import gleam/float
import gleam/int
import gleam/option.{None}
import gleam/regexp
import gleam/string
import kata/ast.{
  FloatMax, FloatMin, IntMax, IntMin, MaxLength, MinLength, Pattern,
}
import kata/error
import kata/schema.{type Schema}

/// String must have at least n characters
pub fn min_length(s: Schema(String), n: Int) -> Schema(String) {
  schema.refine_string(s, MinLength(n), fn(str) {
    case string.length(str) >= n {
      True -> Ok(str)
      False ->
        Error([
          error.Error(
            path: [],
            issue: error.RefinementFailed(
              name: "min_length",
              message: "must be at least " <> int.to_string(n) <> " characters",
            ),
            schema_name: None,
          ),
        ])
    }
  })
}

/// String must have at most n characters
pub fn max_length(s: Schema(String), n: Int) -> Schema(String) {
  schema.refine_string(s, MaxLength(n), fn(str) {
    case string.length(str) <= n {
      True -> Ok(str)
      False ->
        Error([
          error.Error(
            path: [],
            issue: error.RefinementFailed(
              name: "max_length",
              message: "must be at most " <> int.to_string(n) <> " characters",
            ),
            schema_name: None,
          ),
        ])
    }
  })
}

/// String must match a regex pattern
pub fn matches(s: Schema(String), pattern: String) -> Schema(String) {
  schema.refine_string(s, Pattern(pattern), fn(str) {
    case regexp.from_string(pattern) {
      Ok(re) -> {
        case regexp.check(re, str) {
          True -> Ok(str)
          False ->
            Error([
              error.Error(
                path: [],
                issue: error.RefinementFailed(
                  name: "matches",
                  message: "must match pattern " <> pattern,
                ),
                schema_name: None,
              ),
            ])
        }
      }
      Error(_) ->
        Error([
          error.Error(
            path: [],
            issue: error.RefinementFailed(
              name: "matches",
              message: "invalid regex pattern: " <> pattern,
            ),
            schema_name: None,
          ),
        ])
    }
  })
}

/// String must look like an email (simple pattern check)
pub fn email(s: Schema(String)) -> Schema(String) {
  matches(s, "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
}

/// Int must be >= n
pub fn min(s: Schema(Int), n: Int) -> Schema(Int) {
  schema.refine_int(s, IntMin(n), fn(val) {
    case val >= n {
      True -> Ok(val)
      False ->
        Error([
          error.Error(
            path: [],
            issue: error.RefinementFailed(
              name: "min",
              message: "must be at least " <> int.to_string(n),
            ),
            schema_name: None,
          ),
        ])
    }
  })
}

/// Int must be <= n
pub fn max(s: Schema(Int), n: Int) -> Schema(Int) {
  schema.refine_int(s, IntMax(n), fn(val) {
    case val <= n {
      True -> Ok(val)
      False ->
        Error([
          error.Error(
            path: [],
            issue: error.RefinementFailed(
              name: "max",
              message: "must be at most " <> int.to_string(n),
            ),
            schema_name: None,
          ),
        ])
    }
  })
}

/// Float must be >= n
pub fn float_min(s: Schema(Float), n: Float) -> Schema(Float) {
  schema.refine_float(s, FloatMin(n), fn(val) {
    case val >=. n {
      True -> Ok(val)
      False ->
        Error([
          error.Error(
            path: [],
            issue: error.RefinementFailed(
              name: "float_min",
              message: "must be at least " <> float.to_string(n),
            ),
            schema_name: None,
          ),
        ])
    }
  })
}

/// Float must be <= n
pub fn float_max(s: Schema(Float), n: Float) -> Schema(Float) {
  schema.refine_float(s, FloatMax(n), fn(val) {
    case val <=. n {
      True -> Ok(val)
      False ->
        Error([
          error.Error(
            path: [],
            issue: error.RefinementFailed(
              name: "float_max",
              message: "must be at most " <> float.to_string(n),
            ),
            schema_name: None,
          ),
        ])
    }
  })
}
