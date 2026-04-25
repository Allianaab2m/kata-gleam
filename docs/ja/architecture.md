# kata 内部アーキテクチャ

このドキュメントは、**アダプター開発者**やコントリビューターが kata の内部構造を理解するためのものです。Value 中間表現、AST システム、Schema の内部構造、Format トレイト、エラー伝播について解説します。

## 目次

- [概要](#概要)
- [データフロー](#データフロー)
- [Value: 中間表現](#value-中間表現)
- [Schema の内部構造](#schema-の内部構造)
- [AST システム](#ast-システム)
- [エラーシステム](#エラーシステム)
- [Format トレイト](#format-トレイト)
- [フォーマットアダプターの作成](#フォーマットアダプターの作成)
- [リファインメントの内部実装](#リファインメントの内部実装)
- [モジュール依存グラフ](#モジュール依存グラフ)

---

## 概要

kata のアーキテクチャは、`Value` を中心とした**ハブ・アンド・スポーク型**です：

```
ワイヤーフォーマット (JSON, Form, YAML, ...)
        |                   ^
        | parse             | serialize
        v                   |
      Value  <--- hub --->  Value
        |                   ^
        | decode            | encode
        v                   |
   Gleam 型 (User, Order, ...)
```

この設計の意味：
- **スキーマ**は `Value` のみを知っていればよく、ワイヤーフォーマットについて知る必要がありません。
- **フォーマットアダプター**は自分のフォーマットと `Value` の変換だけを担当し、スキーマについて知る必要がありません。
- 新しいワイヤーフォーマットの追加に、既存スキーマの変更は不要です。

---

## データフロー

### デコード（ワイヤーフォーマット -> Gleam 型）

```
生入力 --[Format.parse]--> Value --[Schema.decode]--> Result(a, List(Error))
```

1. フォーマットアダプターの `parse` 関数が生入力（例: JSON 文字列）を `Value` ツリーに変換します。
2. スキーマの `decode` 関数が `Value` ツリーを走査し、型付きの Gleam 値を生成するか、構造化されたエラーのリストを返します。

### エンコード（Gleam 型 -> ワイヤーフォーマット）

```
型付き値 --[Schema.encode]--> Value --[Format.serialize]--> Result(raw, String)
```

1. スキーマの `encode` 関数が型付き値を `Value` ツリーに変換します。
2. フォーマットアダプターの `serialize` 関数が `Value` ツリーをワイヤーフォーマットに変換します。

---

## Value: 中間表現

`kata/value.gleam` で定義されています：

```gleam
pub type Value {
  VNull
  VBool(Bool)
  VInt(Int)
  VFloat(Float)
  VString(String)
  VList(List(Value))
  VObject(List(#(String, Value)))
}
```

### 設計判断

**`VObject` が `Dict` ではなく `List(#(String, Value))` を使用する理由：**
- 挿入順序を保持します（一部のワイヤーフォーマットでは重要）。
- デコード時、重複キーがあった場合は最初の出現が優先されます。
- エンコード時、スキーマはフィールドを定義順に生成します。

**`VInt` と `VFloat` が分離されている理由：**
- JSON のようにフォーマットによっては整数と浮動小数点数を区別します。フォームデータのように区別しないフォーマットもあります。
- `coerce` モジュールが文字列ベースフォーマットのギャップを埋めます。

**`VNull` が明示的な理由：**
- 「フィールドが存在しない」と「フィールドが null」を区別できます。
- `optional` スキーマは両方を `None` として扱います。

### ユーティリティ

```gleam
pub fn classify(v: Value) -> String
```

人間が読める型名を返します：`"null"`, `"bool"`, `"int"`, `"float"`, `"string"`, `"list"`, `"object"`。`TypeMismatch` エラーメッセージで使用されます。

### アダプターでの `parse` 実装

アダプターは生の表現をこの `Value` ツリーに変換する必要があります。基本ルール：

1. **ネイティブの null を `VNull` にマッピング。**
2. **ブール値を `VBool` にマッピング。**
3. **整数を `VInt`、浮動小数点数を `VFloat` にマッピング。** フォーマットが型を区別する場合はそれぞれに。文字列ベースのフォーマット（全ての値が文字列）では全てを `VString` にマッピングし、`coerce` スキーマに頼ります。
4. **配列/リストを `VList` にマッピング。**
5. **オブジェクト/マップを `VObject`** として `List(#(String, Value))` にマッピング。可能であればキー順序を保持してください。

---

## Schema の内部構造

`kata/schema.gleam` で定義されています：

```gleam
pub opaque type Schema(a) {
  Schema(
    decode: fn(Value) -> Result(a, List(Error)),
    encode: fn(a) -> Value,
    ast: Ast,
    dummy: fn() -> a,
  )
}
```

スキーマは 4 つの関数/値を束ねた不透明型です：

| フィールド | 目的 |
|---|---|
| `decode` | `Value -> Result(a, List(Error))` — Value ツリーをパース・バリデーション |
| `encode` | `a -> Value` — 型付き値を Value に変換 |
| `ast` | `Ast` — イントロスペクション用の構造記述 |
| `dummy` | `fn() -> a` — デフォルト値を生成（フィールドチェーンの AST 構築時に使用） |

### `dummy` 関数

`dummy` フィールドは特に注意が必要です。これはフィールドビルダーパターンにおける鶏と卵の問題を解決するために存在します。

レコードスキーマを構築する場合：
```gleam
use name <- kata.field("name", kata.string(), fn(u: User) { u.name })
use age <- kata.field("age", kata.int(), fn(u: User) { u.age })
kata.done(User(name:, age:))
```

スキーマ全体の AST は即座に構築される必要があります。そのために kata は継続チェーンをダミー値で呼び出し、完全なフィールド構造を発見します：

1. `field("name", string(), ...)` は、次にどのフィールドが来るかを発見するためにダミーの `String` で継続を呼び出す必要があります。
2. 継続は別の `field(...)` を返し、再びダミー値が必要になります。
3. `done(...)` に到達するまでこれが繰り返されます。

プリミティブスキーマのダミーは自明です（`""`, `0`, `0.0`, `False`）。`brand` と `transform` ではユーザーがダミー関数を提供します。`lazy` ではダミーは無限再帰を避けるために遅延されます。

### フィールド構築の詳細

`field` 関数の動作：
1. **デコード:** `VObject` から `key` を検索し、`schema` で値をデコードし、結果を `next` に渡します。
2. **エンコード:** `get(final_value)` でフィールドを抽出し、`schema` でエンコードし、`#(key, encoded)` をオブジェクトの先頭に追加します。
3. **AST:** 継続をダミー値で評価して残りのフィールドを発見します。全ての `FieldSpec` エントリを `AstObject` に収集します。

`optional_field` 関数も同様ですが：
- デコード時：キーが存在しないか値が `VNull` の場合、エラーではなく `default` を使用します。
- AST：`FieldSpec` を `optional: True` としてマークします。

### タグ付きユニオンの内部実装

`tagged_union(discriminator, get_tag, variants)`:

**デコード：**
1. `VObject` を期待します。
2. `discriminator` フィールド（例: `"kind"`）を検索します。
3. タグ文字列をバリアントリストとマッチングします。
4. 一致するバリアントのスキーマでデコードします。
5. どのバリアントにも一致しない場合、`UnionNoMatch` エラーを返します。

**エンコード：**
1. `get_tag(value)` でタグを決定します。
2. 一致するバリアントスキーマを見つけます。
3. そのスキーマでエンコードします（`VObject` が生成されます）。
4. `#(discriminator, VString(tag))` をオブジェクトの先頭に追加します。

**AST：**
- `AstUnion(discriminator, variants)` を生成します。各バリアントは `#(tag, ast)` です。
- 各バリアントの AST はバリアントスキーマに対して `to_ast` を呼び出して計算されます。

---

## AST システム

`kata/ast.gleam` で定義されています：

```gleam
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
  AstTransformed(name: Option(String), base: Ast)
  AstBrand(name: String, base: Ast)
}

pub type FieldSpec {
  FieldSpec(key: String, ast: Ast, optional: Bool)
}
```

### 目的

AST は**パブリック**であり、エコシステムツールのために設計されています：

- **JSON Schema 生成** (`kata/json_schema`): AST を走査して JSON Schema Draft 7 を生成します。
- **フォーム生成**: AST を走査して適切な入力タイプとバリデーション属性を持つフォームフィールドを構築します。
- **API ドキュメント**: フィールド名、型、制約、オプショナリティを抽出します。
- **コード生成**: 他の言語で型やバリデータを生成します。

### リファインメント型

リファインメントは AST にメタデータとして直接格納されます：

```gleam
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
```

これにより、エコシステムツールはスキーマを実行せずに制約を抽出できます。

### ラッパーノード

**`AstBrand(name, base)`：**
- ベース AST をブランド名でラップします。
- ツールは名前を表示に使用でき（例: `"Email"`, `"UserId"`）、`base` をアンラップして内部構造を確認できます。

**`AstTransformed(name, base)`：**
- `transform` スキーマのベース AST をラップします。
- `name` は変換に名前がある場合 `Some("...")`、ない場合 `None` です。
- ツールは通常、構造情報のために `base` を透視すべきです。

**`AstLazy(thunk)`：**
- 再帰スキーマのために AST 評価を遅延させます。
- **ツールはこれを処理する必要があります：** サンクを呼び出して実際の AST を取得しますが、無限再帰に対するガードが必要です（例: 訪問済みセットや深さ制限を使用）。

### AST の走査

例：オブジェクトスキーマから全てのフィールド名を抽出する。

```gleam
fn field_names(ast: Ast) -> List(String) {
  case ast {
    AstObject(fields) -> list.map(fields, fn(f) { f.key })
    AstBrand(_, base) -> field_names(base)
    AstTransformed(_, base) -> field_names(base)
    AstLazy(thunk) -> field_names(thunk())
    _ -> []
  }
}
```

---

## エラーシステム

`kata/error.gleam` で定義されています：

```gleam
pub type Error {
  Error(
    path: List(PathSegment),
    issue: Issue,
    schema_name: Option(String),
  )
}

pub type PathSegment {
  Key(String)
  Index(Int)
  Variant(String)
}

pub type Issue {
  TypeMismatch(expected: String, got: String)
  MissingField(name: String)
  RefinementFailed(name: String, message: String)
  UnionNoMatch(discriminator: String, tried: List(String), got: String)
  Custom(message: String)
}
```

### パスの構築

エラーは発生時点で空のパスで作成されます。ネストされたスキーマをバブルアップする際、各レイヤーがパスセグメントをプリペンドします：

```
// 内部エラー（発生時点で作成）：
Error(path: [], issue: TypeMismatch("string", "int"), schema_name: None)

// field("name", ...) を通過後：
Error(path: [Key("name")], issue: TypeMismatch("string", "int"), schema_name: None)

// field("user", ...) を通過後：
Error(path: [Key("user"), Key("name")], issue: TypeMismatch("string", "int"), schema_name: None)

// フォーマット後: "$.user.name: expected string, got int"
```

`prepend_path(errors, segment)` ユーティリティがこれを処理します。

### エラー蓄積戦略

- **リスト：** 全てのアイテムがデコードされます。各アイテムのエラーは `Index(n)` パスセグメントで蓄積されます。
- **オブジェクト：** 欠落した必須フィールドは `MissingField` エラーを生成します。他のフィールドエラーは蓄積されます。
- **ユニオン：** 一致するバリアントのみがデコードされます。どのバリアントにも一致しない場合、単一の `UnionNoMatch` エラーが生成されます。

---

## Format トレイト

`kata/format.gleam` で定義されています：

```gleam
pub type Format(raw) {
  Format(
    name: String,
    parse: fn(raw) -> Result(Value, String),
    serialize: fn(Value) -> Result(raw, String),
    mode: ParseMode,
  )
}

pub type ParseMode {
  Strict
  Coerce
}
```

### フィールド

| フィールド | 説明 |
|---|---|
| `name` | 人間が読めるフォーマット名（例: `"json"`, `"form"`）— エラーメッセージで使用 |
| `parse` | 生入力を `Value` ツリーに変換するか、エラー文字列を返す |
| `serialize` | `Value` ツリーを生出力に変換するか、エラー文字列を返す |
| `mode` | `Strict`（型が正確に一致する必要）または `Coerce`（文字列からの型強制を許可） |

### `ParseMode`

`mode` フィールドはスキーマ利用者にどのプリミティブを使うべきかを示します：

- **`Strict`**（例: JSON）：`kata.int()`, `kata.float()`, `kata.bool()` を使用 — 値はネイティブ型として届きます。
- **`Coerce`**（例: フォームデータ、環境変数）：`coerce.int()`, `coerce.float()`, `coerce.bool()` を使用 — 値は文字列として届き、型強制が必要です。

`mode` は情報提供目的です — 適切なプリミティブを選ぶのはスキーマ作成者の責任です。kata は強制モードと厳格モードを自動的に切り替えません。

### `DecodeError`

```gleam
pub type DecodeError {
  ParseError(message: String)
  SchemaError(errors: List(Error))
}
```

`format.decode` は 2 つの失敗モードを分離します：
- `ParseError`: 生入力が不正（例: 無効な JSON 構文）。
- `SchemaError`: 入力はパース成功したがスキーマに不一致。

この区別により、呼び出し側は適切なエラーメッセージを提供できます（例: 「無効な JSON」vs「フィールド X が見つかりません」）。

---

## フォーマットアダプターの作成

新しいワイヤーフォーマット（例: YAML, TOML, MessagePack）のサポートを追加するには：

### 1. 新しい Gleam パッケージを作成

```
gleam new kata_yaml
```

`gleam.toml` に `kata` を依存関係として追加します。

### 2. `parse` と `serialize` を実装

フォーマットのネイティブ表現と `Value` の間のマッピング：

```gleam
import kata/value.{type Value, VBool, VFloat, VInt, VList, VNull, VObject, VString}

pub fn parse(yaml_string: String) -> Result(Value, String) {
  // YAML パースライブラリを使って文字列をパース。
  // 各 YAML ノードを対応する Value バリアントに変換：
  //   YAML null       -> VNull
  //   YAML boolean    -> VBool(b)
  //   YAML integer    -> VInt(n)
  //   YAML float      -> VFloat(f)
  //   YAML string     -> VString(s)
  //   YAML sequence   -> VList(items)   (各アイテムを再帰的に変換)
  //   YAML mapping    -> VObject(pairs) (各値を再帰的に変換)
  todo
}

pub fn serialize(value: Value) -> Result(String, String) {
  // Value を YAML 文字列に変換：
  //   VNull       -> YAML null
  //   VBool(b)    -> YAML boolean
  //   VInt(n)     -> YAML integer
  //   VFloat(f)   -> YAML float
  //   VString(s)  -> YAML string
  //   VList(items) -> YAML sequence
  //   VObject(pairs) -> YAML mapping
  todo
}
```

### 3. `Format` レコードを作成

```gleam
import kata/format.{type Format, Format, Strict}

pub fn format() -> Format(String) {
  Format(
    name: "yaml",
    parse: parse,
    serialize: fn(v) { Ok(serialize_to_string(v)) },
    mode: Strict,  // 文字列ベースのフォーマットなら Coerce
  )
}
```

### 4. （任意）便利関数を追加

```gleam
import kata/error.{type Error}

pub type YamlError {
  ParseError(message: String)
  SchemaError(errors: List(Error))
}

pub fn decode_yaml(
  schema: kata.Schema(a),
  yaml_string: String,
) -> Result(a, YamlError) {
  case parse(yaml_string) {
    Error(msg) -> Error(ParseError(msg))
    Ok(value) ->
      case kata.decode(schema, value) {
        Error(errs) -> Error(SchemaError(errs))
        Ok(result) -> Ok(result)
      }
  }
}

pub fn encode_yaml(schema: kata.Schema(a), value: a) -> String {
  let v = kata.encode(schema, value)
  serialize_to_string(v)
}
```

### 5. `ParseMode` の選択

- フォーマットがネイティブ型（null, bool, int, float, string, array, object）を持つ場合 — `Strict` を使用。
- フォーマットが文字列ベース（例: フォームデータで `age=30` が `"30"` として届く）の場合 — `Coerce` を使用。

フォーマットが `Coerce` を使う場合、利用者は厳格なプリミティブの代わりに `coerce.int()`, `coerce.float()`, `coerce.bool()` を使用すべきです。

### リファレンス実装

完全なリファレンス実装として `kata_json` を参照してください：
- `kata_json/src/kata_json.gleam` — `gleam/json` を使用した JSON フォーマットアダプター。

---

## リファインメントの内部実装

リファインメントは `kata/schema.gleam` の 3 つの内部関数で実装されています：

```gleam
pub fn refine_string(schema, ref, check) -> Schema(String)
pub fn refine_int(schema, ref, check) -> Schema(Int)
pub fn refine_float(schema, ref, check) -> Schema(Float)
```

それぞれ：
1. **decode 関数をラップ：** ベーススキーマのデコード後に `check` 関数を適用します。`Error(msg)` を返した場合、`RefinementFailed` エラーを生成します。
2. **AST にリファインメントを追加：** AST ノードのリファインメントリストに `StringRef`/`IntRef`/`FloatRef` を追加します。
3. **encode は変更なし：** リファインメントはデコード時のみ有効です。

`kata/refine.gleam` の公開 API はこれらの内部関数を特定のチェック実装で呼び出します：

```gleam
pub fn min_length(schema: Schema(String), n: Int) -> Schema(String) {
  schema.refine_string(schema, ast.MinLength(n), fn(s) {
    case string.length(s) >= n {
      True -> Ok(Nil)
      False -> Error("must be at least " <> int.to_string(n) <> " characters")
    }
  })
}
```

---

## モジュール依存グラフ

```
kata (パブリック再エクスポート)
  |
  +-- kata/schema (コアエンジン)
  |     |-- kata/value
  |     |-- kata/ast
  |     +-- kata/error
  |
  +-- kata/refine (バリデーション)
  |     +-- kata/schema
  |
  +-- kata/coerce (文字列型強制)
  |     +-- kata/schema
  |
  +-- kata/format (アダプタートレイト)
  |     |-- kata/schema
  |     +-- kata/error
  |
  +-- kata/json_schema (スキーマ生成)
  |     +-- kata/ast
  |
  +-- kata/dynamic (FFI 相互変換)
        +-- kata/value

kata_json (別パッケージ)
  |-- kata
  |-- kata/value
  |-- kata/error
  +-- kata/format
```

**重要な原則：** `kata/value` と `kata/ast` は内部依存を持ちません — 純粋なデータ型です。これにより、他の全てのモジュールが安全に依存できる基盤モジュールとなっています。
