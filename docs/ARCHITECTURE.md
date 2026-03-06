# にょわくじ2026 — 技術仕様書

## 技術スタック

| 項目              | 内容                                                                                 |
| ----------------- | ------------------------------------------------------------------------------------ |
| 言語              | [Gleam](https://gleam.run/) — 静的型付き関数型言語 (JavaScript ターゲット)           |
| UI フレームワーク | [Lustre v5](https://hexdocs.pm/lustre/) — Elm アーキテクチャ (Model / Update / View) |
| スタイリング      | Tailwind CSS v4 — `@theme` による CSS 変数ベースのセマンティックトークン管理         |
| デプロイ          | Cloudflare Pages + GitHub Actions                                                    |
| レンダリング      | CSR                                                                                  |

---

## ファイル構成と各モジュールの責務

```
src/
├── nyowa.gleam        # init / update / main (FFI 呼び出しの唯一の境界)
├── nyowa.css          # Tailwind + カスタムテーマ + keyframes
├── nyowa_ffi.mjs      # JavaScript FFI 実装
└── nyowa/
    ├── model.gleam    # 全型定義 / 他モジュールへの依存なし（依存グラフの根）
    ├── ffi.gleam      # FFI 宣言 + delay_msg (ffi.random / ffi.now はここに閉じる)
    ├── content.gleam  # ユーザー向けテキスト定数 / 他モジュールへの依存なし
    ├── fortune.gleam  # ムード判定 + おみくじ選択 (純粋関数)
    ├── evasion.gleam  # 回避パターンロジック (純粋関数)
    └── view.gleam     # UI レンダリング / 文字列は content 参照し hex 直書きしない

test/
├── nyowa_test.gleam   # update / init の統合テスト
├── fortune_test.gleam # fortune.gleam の純粋関数単体テスト
└── evasion_test.gleam # evasion.gleam の純粋関数単体テスト
```

### 型や定数の所在

各モジュールは Single Source of Truth を守る．

| 「何」                   | どこに書く                         | 理由                                        |
| ------------------------ | ---------------------------------- | ------------------------------------------- |
| 型定義                   | `model.gleam`                      | 全モジュールが参照する共通定義              |
| ユーザー向けテキスト     | `content.gleam`                    | テキスト変更時の編集箇所を 1 ファイルに集約 |
| CSS カラーアニメーション | `nyowa.css` の `@theme`            | Tailwind がクラスを自動生成するため         |
| ムード判定ロジック       | `fortune.gleam`                    | 純粋関数として独立してテスト可能にするため  |
| 回避ロジック             | `evasion.gleam`                    | 同上                                        |
| FFI 呼び出し             | `nyowa.gleam` (update / init のみ) | 不純な処理を 1 箇所に集めて，他を純粋に保つ |

---

## アーキテクチャの要点

### Elm アーキテクチャと副作用の境界

- Lustre は Elm アーキテクチャに従う
- `update` はモデルの次状態と「エフェクトの記述」を返す
- 実際の副作用 (`setTimeout` の実行など) は Lustre ランタイムが担う

```
User Event ──► update(Model, Msg) ──► Model' + Effect
                                            │
                                       Lustre Runtime
                                            │
                                   setTimeout / DOM 更新
                                            │
                                       dispatch(Msg) ──► update へ
```

`ffi.delay_msg` は `setTimeout` の記述を返すだけで，それ自体は純粋です．

### 純粋関数 / 不純の境界 (R3 リファクタリング後)

- `update` と `init` が FFI を呼ぶのは意図的な設計
- 不純な責務をこの 2 関数に集中させる
- それ以外はテスト可能な純粋関数にする

| 関数                                                        | 純粋か | 備考                                                 |
| ----------------------------------------------------------- | ------ | ---------------------------------------------------- |
| `determine_mood` / `select_fortune`                         | ✅     | 引数のみに依存                                       |
| `select_evasion_pattern` / `generate_clones` / `random_pos` | ✅     | 乱数や座標は呼び出し側が生成して渡す                 |
| `handle_evasion` / `do_catch`                               | ✅     | 乱数や時刻は引数で受け取る                           |
| `generate_evasion_inputs`                                   | ❌     | FFI 生成をまとめる「準備ステップ」として意図的に不純 |
| `update` / `init`                                           | ❌     | Lustre の不純境界                                    |

この設計により、ロジックの大部分を決定論的な入力でテストできる。

### Impossible States を型で防ぐ

- `Phase` と `EvasionState` の設計方針
- 各フェーズが必要なデータだけを内包
- 型定義は `src/nyowa/model.gleam` が正規の参照先

```
// Cloning の外にクローンリストは存在できない
// → 「Idle なのに clones が残っている」バグはコンパイラレベルで不可能
Evading(Cloning(clones: List(CloneButton)))
```

---

## CSS / スタイリングの方針

- カラーアニメーションの定義は `src/nyowa.css` の `@theme` ブロックが唯一の参照先
- Tailwind v4 が `--color-*` → `text-*`, `bg-*`, `from-*`, `to-*` を自動生成

### 命名ルール

- 本文テキスト色: `--color-body` → `text-body` (`text-[#4A4A4A]` と書かない)
- サブテキスト色: `--color-muted` → `text-muted`
- Mood 別グラデーション: `--color-{mood}-from / -to` → `from-{mood}-from to-{mood}-to`

`view.gleam` のスタイルに hex 値が現れた場合は `nyowa.css` に変数を追加して参照する．

---

## テスト戦略

### 方針

- コンテンツ文字列の定数テストは書かない
  - 変更コストが高くなりフレーキテストになる
  - 空文字列でないことや `None` でないことで代替する
- 視覚アニメーションは自動テストしない (手動確認)
- 純粋関数は境界値を軸に単体テストを書く
- 状態遷移は `update` に実際のメッセージを送り，結果の phase / フィールドを検証する

### FFI のテスト互換性

- `nyowa_ffi.mjs` は Node.js フォールバックを持つ
- テスト環境でも `ffi.random()` / `ffi.now()` が動作する

---

## モバイル対応

### ゴーストクリック防止

#### 問題

- モバイルブラウザでは `touchstart → touchend → click` の順にイベントが発火する
- `touchstart` でボタンを移動しても約 300ms 後に元の座標で `click` が来る

#### 対処

- `recently_touched` フラグ (`Model` フィールド) と `GhostClickExpired` メッセージ
- `e.preventDefault()` を使わず Lustre の `update` 内のフェーズガードで完結

### ボタン位置の制約

`random_pos(viewport, rx, ry)` の座標計算式 (`evasion.gleam` 参照):

```
usable_w = max(viewport_w − 220 − 48, 0)   // button_w=220, margin×2=48
usable_h = max(viewport_h − 64 − 48, 0)    // button_h=64
x = rx × usable_w + 24                     // margin=24
y = ry × usable_h + 24
```

---

## デプロイ

```
git push → GitHub Actions → lustre/dev build → dist/ を Cloudflare Pages へ
```

HTML `<head>` の設定 (Google Fonts など) は `gleam.toml` の `[tools.lustre.html]` セクションで管理します．
