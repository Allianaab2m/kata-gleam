import envoy
import gleeunit
import gleeunit/should
import kata/coerce
import kata/schema
import kata_env

pub fn main() -> Nil {
  gleeunit.main()
}

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

pub fn decode_env_test() {
  // Set test env vars
  envoy.set("DB_HOST", "localhost")
  envoy.set("DB_PORT", "5432")

  kata_env.decode(db_config_schema())
  |> should.equal(Ok(DbConfig("localhost", 5432)))

  // Clean up
  envoy.unset("DB_HOST")
  envoy.unset("DB_PORT")
}

pub fn decode_env_missing_test() {
  envoy.unset("DB_HOST")
  envoy.unset("DB_PORT")

  kata_env.decode(db_config_schema())
  |> should.be_error()
}

pub fn decode_env_invalid_int_test() {
  envoy.set("DB_HOST", "localhost")
  envoy.set("DB_PORT", "not_a_number")

  kata_env.decode(db_config_schema())
  |> should.be_error()

  envoy.unset("DB_HOST")
  envoy.unset("DB_PORT")
}

pub type AppConfig {
  AppConfig(name: String, debug: Bool)
}

fn app_config_schema() {
  use name <- schema.field("APP_NAME", schema.string(), fn(c: AppConfig) {
    c.name
  })
  use debug <- schema.optional_field(
    "APP_DEBUG",
    coerce.bool(),
    False,
    fn(c: AppConfig) { c.debug },
  )
  schema.done(AppConfig(name:, debug:))
}

pub fn decode_env_optional_present_test() {
  envoy.set("APP_NAME", "myapp")
  envoy.set("APP_DEBUG", "true")

  kata_env.decode(app_config_schema())
  |> should.equal(Ok(AppConfig("myapp", True)))

  envoy.unset("APP_NAME")
  envoy.unset("APP_DEBUG")
}

pub fn decode_env_optional_missing_test() {
  envoy.set("APP_NAME", "myapp")
  envoy.unset("APP_DEBUG")

  kata_env.decode(app_config_schema())
  |> should.equal(Ok(AppConfig("myapp", False)))

  envoy.unset("APP_NAME")
}
