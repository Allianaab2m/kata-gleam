import gleam/dict
import gleeunit/should
import kata/coerce
import kata/format
import kata/schema
import kata_env

pub type DbConfig {
  DbConfig(host: String, port: Int)
}

fn db_config_schema() {
  use host <- schema.field("DB_HOST", schema.string(), fn(c: DbConfig) {
    c.host
  })
  use port <- schema.field("DB_PORT", coerce.int(), fn(c: DbConfig) { c.port })
  schema.done(DbConfig(host:, port:))
}

// --- format.decode ---

pub fn format_decode_test() {
  let env = dict.from_list([#("DB_HOST", "localhost"), #("DB_PORT", "5432")])
  format.decode(db_config_schema(), kata_env.format(), env)
  |> should.equal(Ok(DbConfig("localhost", 5432)))
}

pub fn format_decode_missing_field_test() {
  let env = dict.from_list([#("DB_HOST", "localhost")])
  format.decode(db_config_schema(), kata_env.format(), env)
  |> should.be_error()
}

// --- format.encode ---

pub fn format_encode_test() {
  let config = DbConfig("localhost", 5432)
  let assert Ok(env) =
    format.encode(db_config_schema(), kata_env.format(), config)
  dict.get(env, "DB_HOST") |> should.equal(Ok("localhost"))
  dict.get(env, "DB_PORT") |> should.equal(Ok("5432"))
}

// --- roundtrip ---

pub fn roundtrip_test() {
  let config = DbConfig("localhost", 5432)
  let assert Ok(env) =
    format.encode(db_config_schema(), kata_env.format(), config)
  format.decode(db_config_schema(), kata_env.format(), env)
  |> should.equal(Ok(config))
}
