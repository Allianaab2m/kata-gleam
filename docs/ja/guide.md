# kata API ガイド

kata は **Gleam 向けの双方向スキーマライブラリ**です。一つのスキーマ定義でデコード（パース）とエンコード（シリアライズ）の両方を、任意のワイヤーフォーマットに対して行えます。

名前の由来は日本語の **型（かた）** です。

## 目次

- [インストール](#インストール)
- [クイックスタート](#クイックスタート)
- [プリミティブスキーマ](#プリミティブスキーマ)
- [コンテナスキーマ](#コンテナスキーマ)
- [レコード（オブジェクト）スキーマ](#レコードオブジェクトスキーマ)
- [タグ付きユニオン](#タグ付きユニオン)
- [リファインメント（バリデーション制約）](#リファインメントバリデーション制約)
- [Brand（不透明型）](#brand不透明型)
- [Transform](#transform)
- [再帰スキーマ](#再帰スキーマ)
- [フォーマットアダプター](#フォーマットアダプター)
- [スマートコンストラクタ](#スマートコンストラクタ)
- [JSON Schema 生成](#json-schema-生成)
- [エラーハンドリング](#エラーハンドリング)
- [API リファレンス](#api-リファレンス)

---

## インストール

`gleam.toml` に kata と必要なフォーマットアダプターを追加してください：

```toml
[dependencies]
kata = ">= 0.1.0"
kata_json = ">= 0.1.0"   # JSON サポートが必要な場合
```

## クイックスタート

```gleam
import kata
import kata_json

// 1. 型を定義
pub type User {
  User(name: String, age: Int)
}

// 2. スキーマを一度だけ定義 — デコード・エンコード両方に対応
fn user_schema() -> kata.Schema(User) {
  use name <- kata.field("name", kata.string(), fn(u: User) { u.name })
  use age <- kata.field("age", kata.int(), fn(u: User) { u.age })
  kata.done(User(name:, age:))
}

// 3. JSON からデコード
let json = "{\"name\":\"Alice\",\"age\":30}"
let assert Ok(user) = kata_json.decode_json(user_schema(), json)
// -> User("Alice", 30)

// 4. JSON へエンコード
let json_out = kata_json.encode_json(user_schema(), user)
// -> "{\"name\":\"Alice\",\"age\":30}"
```

---

## プリミティブスキーマ

4 つのプリミティブ型に対するスキーマが用意されています：

| 関数 | 型 | 受け入れる Value |
|---|---|---|
| `kata.string()` | `Schema(String)` | `VString` |
| `kata.int()` | `Schema(Int)` | `VInt` |
| `kata.float()` | `Schema(Float)` | `VFloat` |
| `kata.bool()` | `Schema(Bool)` | `VBool` |

```gleam
let s = kata.string()
let assert Ok("hello") = kata.decode(s, VString("hello"))

let encoded = kata.encode(s, "hello")
// -> VString("hello")
```

### 型強制プリミティブ（Coerced Primitives）

フォームデータや環境変数など、全ての値が文字列として届くフォーマット向けに `kata/coerce` を使います：

| 関数 | 受け入れる Value |
|---|---|
| `coerce.int()` | `VInt` または整数としてパース可能な `VString` |
| `coerce.float()` | `VFloat`、`VInt`、または浮動小数点数としてパース可能な `VString` |
| `coerce.bool()` | `VBool` または `VString("true"/"false")` |

```gleam
import kata/coerce

let s = coerce.int()
let assert Ok(42) = kata.decode(s, VString("42"))
let assert Ok(42) = kata.decode(s, VInt(42))
```

---

## コンテナスキーマ

### List

```gleam
let int_list = kata.list(kata.int())

let encoded = kata.encode(int_list, [1, 2, 3])
// -> VList([VInt(1), VInt(2), VInt(3)])

let assert Ok([1, 2, 3]) = kata.decode(int_list, encoded)
```

### Optional

`VNull`（またはフィールドの欠如）を `None` としてデコードします：

```gleam
import gleam/option.{None, Some}

let opt = kata.optional(kata.string())

let assert Ok(Some("hi")) = kata.decode(opt, VString("hi"))
let assert Ok(None) = kata.decode(opt, VNull)
```

### Dict

キー・バリュー型のマップをデコード/エンコードします。キーと値にそれぞれスキーマを指定します：

```gleam
let d = kata.dict(kata.string(), kata.int())

let input = VObject([#("x", VInt(1)), #("y", VInt(2))])
let assert Ok(result) = kata.decode(d, input)
// result == dict.from_list([#("x", 1), #("y", 2)])
```

---

## レコード（オブジェクト）スキーマ

レコードは `field`、`optional_field`、`done` の継続渡しパターンで構築します：

```gleam
pub type User {
  User(name: String, age: Int, bio: option.Option(String))
}

fn user_schema() -> kata.Schema(User) {
  // 必須フィールド: キー, スキーマ, ゲッター（エンコード用）, 継続
  use name <- kata.field("name", kata.string(), fn(u: User) { u.name })
  use age <- kata.field("age", kata.int(), fn(u: User) { u.age })
  // オプショナルフィールド: キー, スキーマ, デフォルト値, ゲッター, 継続
  use bio <- kata.optional_field(
    "bio", kata.string(), option.None, fn(u: User) { u.bio },
  )
  kata.done(User(name:, age:, bio:))
}
```

### `kata.field(key, schema, get, next)`

**必須**フィールドを宣言します。

| パラメータ | 説明 |
|---|---|
| `key` | ワイヤーフォーマット上のフィールド名（例: `"name"`） |
| `schema` | このフィールドの値に対するスキーマ |
| `get` | ゲッター関数：レコードからこのフィールドを取り出す（エンコード時に使用） |
| `next` | 継続：デコードされた値を受け取り、残りのスキーマを返す |

### `kata.optional_field(key, schema, default, get, next)`

**オプショナル**フィールドを宣言します。フィールドが存在しないか `VNull` の場合、`default` が使われます。

### `kata.done(value)`

フィールドチェーンを終端し、構築された値を返します。

### ネストされたオブジェクト

スキーマは自然に合成してネストできます：

```gleam
pub type Profile {
  Profile(user: User, website: String)
}

fn profile_schema() -> kata.Schema(Profile) {
  use user <- kata.field("user", user_schema(), fn(p: Profile) { p.user })
  use website <- kata.field("website", kata.string(), fn(p: Profile) { p.website })
  kata.done(Profile(user:, website:))
}
```

---

## タグ付きユニオン

判別フィールド（discriminator）でバリアントを決定する直和型に使います：

```gleam
pub type Shape {
  Circle(radius: Float)
  Rectangle(width: Float, height: Float)
}

fn shape_schema() -> kata.Schema(Shape) {
  kata.tagged_union(
    "kind",                          // 判別フィールド名
    fn(s: Shape) {                   // タグ抽出関数（エンコード用）
      case s {
        Circle(_) -> "circle"
        Rectangle(_, _) -> "rectangle"
      }
    },
    [                                // バリアントリスト: #(タグ, スキーマ)
      #("circle", {
        use r <- kata.field("radius", kata.float(), fn(s: Shape) {
          case s { Circle(r) -> r, _ -> 0.0 }
        })
        kata.done(Circle(r))
      }),
      #("rectangle", {
        use w <- kata.field("width", kata.float(), fn(s: Shape) {
          case s { Rectangle(w, _) -> w, _ -> 0.0 }
        })
        use h <- kata.field("height", kata.float(), fn(s: Shape) {
          case s { Rectangle(_, h) -> h, _ -> 0.0 }
        })
        kata.done(Rectangle(w, h))
      }),
    ],
  )
}
```

**デコード時:** 判別フィールド (`"kind"`) を読み取り、タグに一致するバリアントスキーマでデコードします。

**エンコード時:** タグ抽出関数でタグを決定し、対応するスキーマでエンコード後、判別フィールドを注入します。

JSON の例：
```json
{"kind": "circle", "radius": 5.0}
{"kind": "rectangle", "width": 3.0, "height": 4.0}
```

---

## リファインメント（バリデーション制約）

エンコードに影響を与えずにバリデーション制約を追加します。`kata/refine` をインポートしてください：

### 文字列リファインメント

```gleam
import kata/refine

let name_schema =
  kata.string()
  |> refine.min_length(1)
  |> refine.max_length(100)

let email_schema =
  kata.string()
  |> refine.email()

let code_schema =
  kata.string()
  |> refine.matches("^[A-Z]{3}-\\d{4}$")
```

### 整数リファインメント

```gleam
let age_schema =
  kata.int()
  |> refine.min(0)
  |> refine.max(150)
```

### 浮動小数点リファインメント

```gleam
let score_schema =
  kata.float()
  |> refine.float_min(0.0)
  |> refine.float_max(100.0)
```

リファインメントは**合成可能**です。同じスキーマに複数チェーンできます。全ての制約はデコード時にチェックされ、違反は `RefinementFailed` エラーとして報告されます。

リファインメントは **AST** にも反映され、**JSON Schema** の出力にも現れます。

---

## Brand（不透明型）

`kata.brand` はスキーマを名前付きの型でラップします。不透明な "newtype" ラッパーに便利です：

```gleam
pub type Email {
  Email(String)
}

fn email_schema() -> kata.Schema(Email) {
  kata.string()
  |> refine.email()
  |> kata.brand("Email", Email, fn(e: Email) {
    let Email(s) = e
    s
  })
}
```

| パラメータ | 説明 |
|---|---|
| `name` | ブランド名（AST と JSON Schema の `title` に反映） |
| `wrap` | コンストラクタ: `a -> b` |
| `unwrap` | 抽出関数: `b -> a` |

---

## Transform

`kata.transform` はデコード/エンコード時にカスタム変換を適用します：

```gleam
pub type Percent {
  Percent(Int)
}

fn percent_schema() -> kata.Schema(Percent) {
  kata.int()
  |> kata.transform(
    "Percent",
    fn(n) {                          // forward: デコード方向
      case n >= 0 && n <= 100 {
        True -> Ok(Percent(n))
        False -> Error("must be 0-100")
      }
    },
    fn(p) { let Percent(n) = p; n }, // backward: エンコード方向
    fn() { Percent(0) },             // ダミー値（AST 構築用）
  )
}
```

| パラメータ | 説明 |
|---|---|
| `name` | 変換名（AST に反映） |
| `forward` | `a -> Result(b, String)` — デコード方向の変換 |
| `backward` | `b -> a` — エンコード方向の変換（forward の逆関数） |
| `dummy` | `fn() -> b` — AST 構築用のダミー値生成関数 |

---

## 再帰スキーマ

循環参照を断ち切るために `kata.lazy` を使います：

```gleam
pub type Tree {
  Leaf(Int)
  Node(left: Tree, right: Tree)
}

fn tree_schema() -> kata.Schema(Tree) {
  kata.tagged_union(
    "kind",
    fn(t: Tree) {
      case t { Leaf(_) -> "leaf", Node(_, _) -> "node" }
    },
    [
      #("leaf", {
        use v <- kata.field("value", kata.int(), fn(t: Tree) {
          case t { Leaf(n) -> n, _ -> 0 }
        })
        kata.done(Leaf(v))
      }),
      #("node", {
        use l <- kata.field("left", kata.lazy(tree_schema), fn(t: Tree) {
          case t { Node(l, _) -> l, _ -> Leaf(0) }
        })
        use r <- kata.field("right", kata.lazy(tree_schema), fn(t: Tree) {
          case t { Node(_, r) -> r, _ -> Leaf(0) }
        })
        kata.done(Node(l, r))
      }),
    ],
  )
}
```

`kata.lazy(f)` は **サンク** (`fn() -> Schema(a)`) を受け取るため、スキーマは必要なときにのみ評価され、無限再帰を防ぎます。

---

## フォーマットアダプター

kata はフォーマット非依存です。`Format` 抽象化により、同じスキーマを JSON、フォームデータ、その他のワイヤーフォーマットで使えます。

### フォーマットの使い方

```gleam
import kata/format
import kata_json

// デコード
let result = format.decode(user_schema(), kata_json.format(), json_string)
case result {
  Ok(user) -> // 成功
  Error(format.ParseError(msg)) -> // JSON 構文エラー
  Error(format.SchemaError(errs)) -> // JSON は正しいがスキーマに不一致
}

// エンコード
let assert Ok(json) = format.encode(user_schema(), kata_json.format(), user)
```

重要なポイント：`format.decode` は **パースエラー**（構文不正）と **スキーマエラー**（データ形状の不一致）を `DecodeError` 型で区別します：

```gleam
pub type DecodeError {
  ParseError(message: String)
  SchemaError(errors: List(Error))
}
```

### 便利関数 (kata_json)

JSON のみ必要な場合、`kata_json` のショートハンド関数が使えます：

```gleam
import kata_json

let assert Ok(user) = kata_json.decode_json(user_schema(), json_string)
let json_out = kata_json.encode_json(user_schema(), user)
```

### 独自アダプターの作成

詳しくは [アーキテクチャ: フォーマットアダプターの作成](architecture.md#フォーマットアダプターの作成) を参照してください。

---

## スマートコンストラクタ

中間の `Value` 表現を経由せずに、プリミティブ値をスキーマで直接バリデーションします：

```gleam
pub type Email {
  Email(String)
}

fn email_schema() -> kata.Schema(Email) {
  kata.string()
  |> refine.email()
  |> kata.brand("Email", Email, fn(e: Email) { let Email(s) = e; s })
}

// スマートコンストラクタ
pub fn new_email(s: String) -> Result(Email, List(kata.Error)) {
  kata.from_string(email_schema(), s)
}
```

利用可能なスマートコンストラクタ：

| 関数 | 入力型 |
|---|---|
| `kata.from_string(schema, s)` | `String` |
| `kata.from_int(schema, n)` | `Int` |
| `kata.from_float(schema, f)` | `Float` |
| `kata.from_bool(schema, b)` | `Bool` |

各関数はプリミティブ値を `Value` にラップし、スキーマのデコードを通して結果を返します。ドメイン型の構築時バリデーションに有用です。

---

## JSON Schema 生成

任意のスキーマから JSON Schema (Draft 7) を生成します：

```gleam
import kata/json_schema

let schema_str = json_schema.to_json_schema(user_schema())
```

出力例：
```json
{
  "type": "object",
  "properties": {
    "name": { "type": "string" },
    "age": { "type": "integer" }
  },
  "required": ["name", "age"]
}
```

リファインメントとブランドは出力に反映されます：
- `min_length` / `max_length` -> `minLength` / `maxLength`
- `min` / `max` -> `minimum` / `maximum`
- `matches` -> `pattern`
- `brand` -> `title`

---

## エラーハンドリング

デコードエラーは構造化されており、正確なパス情報が含まれます：

```gleam
import kata/error

case kata.decode(user_schema(), bad_value) {
  Ok(user) -> // ...
  Error(errors) -> {
    // 全エラーを人間が読める文字列にフォーマット
    let msg = error.format_errors(errors)
    // -> "$.name: expected string, got int\n$.age: missing required field \"age\""
  }
}
```

### エラー構造

```gleam
pub type Error {
  Error(
    path: List(PathSegment),  // データ内の位置
    issue: Issue,             // 何が問題だったか
    schema_name: Option(String),
  )
}
```

### パスセグメント

| バリアント | 意味 | 例 |
|---|---|---|
| `Key(name)` | オブジェクトフィールド | `$.user` |
| `Index(n)` | リスト要素 | `$.items[0]` |
| `Variant(tag)` | ユニオンバリアント | `$.shape<circle>` |

### Issue の種類

| バリアント | 発生条件 |
|---|---|
| `TypeMismatch(expected, got)` | 値の型が不正（例: string を期待したが int だった） |
| `MissingField(name)` | 必須フィールドが存在しない |
| `RefinementFailed(name, message)` | バリデーション制約に違反 |
| `UnionNoMatch(discriminator, tried, got)` | どのユニオンバリアントにも一致しなかった |
| `Custom(message)` | `transform` からのカスタムエラー |

---

## API リファレンス

### コアモジュール (`kata`)

#### プリミティブコンストラクタ
- `string() -> Schema(String)`
- `int() -> Schema(Int)`
- `float() -> Schema(Float)`
- `bool() -> Schema(Bool)`

#### コンテナコンストラクタ
- `list(item: Schema(a)) -> Schema(List(a))`
- `optional(inner: Schema(a)) -> Schema(Option(a))`
- `dict(key_schema: Schema(k), val_schema: Schema(v)) -> Schema(Dict(k, v))`

#### レコード構築
- `field(key: String, schema: Schema(a), get: fn(final) -> a, next: fn(a) -> Schema(final)) -> Schema(final)`
- `optional_field(key: String, schema: Schema(a), default: a, get: fn(final) -> a, next: fn(a) -> Schema(final)) -> Schema(final)`
- `done(value: a) -> Schema(a)`

#### 高度なコンビネータ
- `tagged_union(discriminator: String, get_tag: fn(a) -> String, variants: List(#(String, Schema(a)))) -> Schema(a)`
- `lazy(f: fn() -> Schema(a)) -> Schema(a)`
- `transform(schema: Schema(a), name: String, forward: fn(a) -> Result(b, String), backward: fn(b) -> a, dummy: fn() -> b) -> Schema(b)`
- `brand(base: Schema(a), name: String, wrap: fn(a) -> b, unwrap: fn(b) -> a) -> Schema(b)`

#### 実行
- `decode(schema: Schema(a), value: Value) -> Result(a, List(Error))`
- `encode(schema: Schema(a), value: a) -> Value`
- `to_ast(schema: Schema(a)) -> Ast`

#### スマートコンストラクタ
- `from_string(schema: Schema(a), value: String) -> Result(a, List(Error))`
- `from_int(schema: Schema(a), value: Int) -> Result(a, List(Error))`
- `from_float(schema: Schema(a), value: Float) -> Result(a, List(Error))`
- `from_bool(schema: Schema(a), value: Bool) -> Result(a, List(Error))`

### リファインメント (`kata/refine`)

- `min_length(schema: Schema(String), n: Int) -> Schema(String)`
- `max_length(schema: Schema(String), n: Int) -> Schema(String)`
- `matches(schema: Schema(String), pattern: String) -> Schema(String)`
- `email(schema: Schema(String)) -> Schema(String)`
- `min(schema: Schema(Int), n: Int) -> Schema(Int)`
- `max(schema: Schema(Int), n: Int) -> Schema(Int)`
- `float_min(schema: Schema(Float), n: Float) -> Schema(Float)`
- `float_max(schema: Schema(Float), n: Float) -> Schema(Float)`

### 型強制 (`kata/coerce`)

- `int() -> Schema(Int)`
- `float() -> Schema(Float)`
- `bool() -> Schema(Bool)`

### フォーマット (`kata/format`)

- `decode(schema: Schema(a), fmt: Format(raw), input: raw) -> Result(a, DecodeError)`
- `encode(schema: Schema(a), fmt: Format(raw), value: a) -> Result(raw, String)`

### JSON (`kata_json`)

- `format() -> Format(String)`
- `parse(json: String) -> Result(Value, String)`
- `serialize(value: Value) -> String`
- `decode_json(schema: Schema(a), json: String) -> Result(a, JsonError)`
- `encode_json(schema: Schema(a), value: a) -> String`

### エラーユーティリティ (`kata/error`)

- `prepend_path(errors: List(Error), segment: PathSegment) -> List(Error)`
- `path_to_string(path: List(PathSegment)) -> String`
- `format_error(error: Error) -> String`
- `format_errors(errors: List(Error)) -> String`

### JSON Schema (`kata/json_schema`)

- `to_json_schema(schema: Schema(a)) -> String`
- `ast_to_json_string(ast: Ast) -> String`

### Dynamic 相互変換 (`kata/dynamic`)

- `from_dynamic(dyn: Dynamic) -> Result(Value, String)`
- `to_dynamic(value: Value) -> Dynamic`
