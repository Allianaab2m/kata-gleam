/// kata_wisp — Wisp integration for kata schema validation.
/// Provides middleware that validates request data with kata schemas.
///
/// ```gleam
/// import kata
/// import kata/coerce
/// import kata_wisp
///
/// fn handle_create_user(req: Request) -> Response {
///   use user <- kata_wisp.require_json(req, user_schema())
///   // `user` is fully validated and typed
///   wisp.json_response(kata_json.encode_json(user_schema(), user), 201)
/// }
/// ```

import gleam/json
import gleam/list
import gleam/string
import kata/error
import kata/schema.{type Schema}
import kata/value.{VObject, VString}
import kata_form
import kata_json
import wisp.{type Request, type Response}

/// Validate a JSON request body with a kata schema.
/// Returns 400 if the body is not valid JSON.
/// Returns 422 if the JSON doesn't match the schema.
pub fn require_json(
  request: Request,
  schema: Schema(a),
  next: fn(a) -> Response,
) -> Response {
  use body <- wisp.require_string_body(request)
  case kata_json.decode_json(schema, body) {
    Ok(value) -> next(value)
    Error(kata_json.ParseError(_)) -> wisp.bad_request("invalid JSON")
    Error(kata_json.SchemaError(errs)) ->
      wisp.unprocessable_content()
      |> wisp.json_body(errors_to_json(errs))
  }
}

/// Validate a URL-encoded form body with a kata schema.
/// Uses `kata/coerce` schemas for non-string fields.
/// Returns 400 if the body is not valid form data.
/// Returns 422 if the data doesn't match the schema.
pub fn require_form(
  request: Request,
  schema: Schema(a),
  next: fn(a) -> Response,
) -> Response {
  use form_data <- wisp.require_form(request)
  case kata_form.decode_pairs(schema, form_data.values) {
    Ok(value) -> next(value)
    Error(errs) ->
      wisp.unprocessable_content()
      |> wisp.json_body(errors_to_json(errs))
  }
}

/// Validate query parameters with a kata schema.
/// Uses `kata/coerce` schemas for non-string fields.
/// Returns 422 if query params don't match the schema.
pub fn require_query(
  request: Request,
  schema: Schema(a),
  next: fn(a) -> Response,
) -> Response {
  let pairs = wisp.get_query(request)
  let value = VObject(list.map(pairs, fn(p) { #(p.0, VString(p.1)) }))
  case schema.decode(schema, value) {
    Ok(a) -> next(a)
    Error(errs) ->
      wisp.unprocessable_content()
      |> wisp.json_body(errors_to_json(errs))
  }
}

/// Format kata errors as a JSON response body.
fn errors_to_json(errs: List(error.Error)) -> String {
  let error_items =
    list.map(errs, fn(e) {
      let path = error.path_to_string(e.path)
      let message = error.format_error(e)
      json.object([
        #("path", json.string(path)),
        #("message", json.string(message)),
      ])
    })
  json.object([#("errors", json.preprocessed_array(error_items))])
  |> json.to_string()
}
