import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub type Position {
  Position(x: Float, y: Float)
}

pub type CloneButton {
  CloneButton(pos: Position, is_real: Bool)
}

pub type Mood {
  Furious
  Grumpy
  Neutral
  Rested
  Sleepy
}

pub type Fortune {
  Fortune(rank: String, message: String, mood: Mood)
}

pub type DrawState {
  Spinning
  Paused
  Reversing
  Instant
}

pub type EvasionState {
  Dodging(pos: Position, evade_count: Int)
  Cloning(clones: List(CloneButton))
  Excusing(index: Int, text: String)
  Camouflaging(pos: Position)
  Cooperating
}

pub type Phase {
  Idle
  Evading(state: EvasionState)
  Caught
  Drawing(state: DrawState)
  ShowResult(fortune: Fortune)
}

pub type Model {
  Model(
    phase: Phase,
    page_loaded_at: Float,
    first_interact_at: Option(Float),
    evade_count: Int,
    viewport: #(Float, Float),
    dialogue: Option(String),
    recently_touched: Bool,
  )
}

pub type Msg {
  ButtonHovered
  ButtonTouched
  ButtonClicked(index: Int)
  GhostClickExpired
  ExcuseExpired
  DrawTick
  DrawInterruption(DrawState)
  DrawComplete(Fortune)
  TransitionDone
  PlayAgain
  GotTimestamp(Float)
  GotRandom(Float)
  GotViewport(Float, Float)
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

pub fn init(_flags: Nil) -> #(Model, effect.Effect(Msg)) {
  let model =
    Model(
      phase: Idle,
      page_loaded_at: 0.0,
      first_interact_at: None,
      evade_count: 0,
      viewport: get_viewport_size(),
      dialogue: None,
      recently_touched: False,
    )
  #(model, get_timestamp())
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    GotTimestamp(ts) -> #(Model(..model, page_loaded_at: ts), effect.none())

    GotViewport(w, h) -> #(Model(..model, viewport: #(w, h)), effect.none())

    ButtonHovered -> handle_evasion(model, False)
    ButtonTouched -> handle_evasion(model, True)

    GhostClickExpired -> #(
      Model(..model, recently_touched: False),
      effect.none(),
    )

    ButtonClicked(index) ->
      case model.phase {
        // Dodge: ゴーストクリック猶予中は無視し，それ以外はキャッチ
        Evading(Dodging(_, _)) ->
          case model.recently_touched {
            True -> #(model, effect.none())
            False -> do_catch(model)
          }

        // Clone: 押したボタンが本物か判定し，外れなら残像を消す
        Evading(Cloning(clones)) -> {
          case clone_at(clones, index) {
            Ok(CloneButton(_, True)) -> do_catch(model)
            Ok(CloneButton(_, False)) ->
              #(
                Model(
                  ..model,
                  phase: Evading(Cloning(
                    clones: remove_at_index(clones, index),
                  )),
                  evade_count: model.evade_count + 1,
                  dialogue: Some("それ残像です……"),
                ),
                effect.none(),
              )
            Error(_) -> #(model, effect.none())
          }
        }

        // Excuse: ボタンは disabled なので通常は発火しないが保険として
        Evading(Excusing(_, _)) -> #(model, effect.none())

        // Camo / Cooperate: そのままキャッチ
        Evading(Camouflaging(_)) -> do_catch(model)
        Evading(Cooperating) -> do_catch(model)

        // Idle: ホバー前に直クリックされた場合
        Idle -> #(
          Model(
            ..model,
            phase: ShowResult(placeholder_fortune()),
            first_interact_at: Some(model.page_loaded_at),
            dialogue: None,
          ),
          effect.none(),
        )

        _ -> #(model, effect.none())
      }

    // Excuse タイマー: 次の言い訳 or 最初の画面に移行
    ExcuseExpired ->
      case model.phase {
        Evading(Excusing(index, _)) ->
          case index >= 2 {
            True ->
              // 言い訳 3 回耐えた → 最初の画面に戻す (仕切り直し)
              #(
                Model(
                  ..model,
                  phase: Idle,
                  dialogue: None,
                  recently_touched: False,
                ),
                effect.none(),
              )
            False -> {
              let next_idx = index + 1
              let next_text = excuse_text(next_idx)
              #(
                Model(
                  ..model,
                  phase: Evading(Excusing(index: next_idx, text: next_text)),
                  evade_count: model.evade_count + 1,
                  dialogue: Some(next_text),
                ),
                delay_msg(ExcuseExpired, 2500),
              )
            }
          }
        _ -> #(model, effect.none())
      }

    PlayAgain -> #(
      Model(
        ..model,
        phase: Idle,
        evade_count: 0,
        dialogue: None,
        first_interact_at: None,
        recently_touched: False,
      ),
      effect.none(),
    )

    DrawTick -> #(model, effect.none())
    DrawInterruption(_) -> #(model, effect.none())
    DrawComplete(_) -> #(model, effect.none())
    TransitionDone -> #(model, effect.none())
    GotRandom(_) -> #(model, effect.none())
  }
}

// キャッチ成功 → ShowResult へ遷移
fn do_catch(model: Model) -> #(Model, effect.Effect(Msg)) {
  #(
    Model(..model, phase: ShowResult(placeholder_fortune()), dialogue: None),
    effect.none(),
  )
}

// hover / touchstart のハンドラ共通処理
fn handle_evasion(model: Model, is_touch: Bool) -> #(Model, effect.Effect(Msg)) {
  let touch_eff = case is_touch {
    True -> delay_msg(GhostClickExpired, 500)
    False -> effect.none()
  }
  case model.phase {
    Idle -> {
      let rand = random()
      let #(state, dialogue_text, pattern_eff) =
        select_evasion_pattern(rand, model.viewport)
      #(
        Model(
          ..model,
          phase: Evading(state),
          evade_count: model.evade_count + 1,
          recently_touched: is_touch,
          dialogue: Some(dialogue_text),
          first_interact_at: Some(model.page_loaded_at),
        ),
        effect.batch([pattern_eff, touch_eff]),
      )
    }

    // Dodge 中にまた逃げる
    Evading(Dodging(_, count)) -> {
      let new_evade_count = model.evade_count + 1
      let pos = random_pos(model.viewport)
      #(
        Model(
          ..model,
          phase: Evading(Dodging(pos: pos, evade_count: count + 1)),
          evade_count: new_evade_count,
          dialogue: Some(dodge_dialogue(new_evade_count)),
          recently_touched: is_touch,
        ),
        touch_eff,
      )
    }

    // その他のパターン中はホバー / タッチを無視
    _ -> #(model, effect.none())
  }
}

// 確率テーブルに基づいてパターンを選択する
// Dodge 30% / Clone 20% / Excuse 20% / Camo 15% / Cooperate 15%
fn select_evasion_pattern(
  rand: Float,
  viewport: #(Float, Float),
) -> #(EvasionState, String, effect.Effect(Msg)) {
  case rand <. 0.3 {
    True -> {
      let pos = random_pos(viewport)
      #(Dodging(pos: pos, evade_count: 1), "えっ……にょわ……", effect.none())
    }
    False ->
      case rand <. 0.5 {
        True -> {
          let clones = generate_clones(viewport)
          #(Cloning(clones: clones), "どれが本物でしょ〜にょわ……", effect.none())
        }
        False ->
          case rand <. 0.7 {
            True -> {
              let text = excuse_text(0)
              #(
                Excusing(index: 0, text: text),
                text,
                delay_msg(ExcuseExpired, 2500),
              )
            }
            False ->
              case rand <. 0.85 {
                True -> {
                  let pos = random_pos(viewport)
                  #(
                    Camouflaging(pos: pos),
                    "にょわ……どこだ〜……",
                    effect.none(),
                  )
                }
                False -> #(Cooperating, "しゃーない、引かせてやるか……", effect.none())
              }
          }
      }
  }
}

// 分身ボタンを 3 つ生成 (ランダム 1 つが本物)
fn generate_clones(viewport: #(Float, Float)) -> List(CloneButton) {
  let real_idx = float.round(random() *. 2.0)
  let p0 = random_pos(viewport)
  let p1 = random_pos(viewport)
  let p2 = random_pos(viewport)
  [
    CloneButton(pos: p0, is_real: real_idx == 0),
    CloneButton(pos: p1, is_real: real_idx == 1),
    CloneButton(pos: p2, is_real: real_idx == 2),
  ]
}

// ビューポート内のランダム位置 (ボタンが画面外に出ない)
fn random_pos(viewport: #(Float, Float)) -> Position {
  let #(vp_w, vp_h) = viewport
  let btn_w = 220.0
  let btn_h = 64.0
  let margin = 24.0
  let usable_w = float.max(vp_w -. btn_w -. margin *. 2.0, 0.0)
  let usable_h = float.max(vp_h -. btn_h -. margin *. 2.0, 0.0)
  Position(x: random() *. usable_w +. margin, y: random() *. usable_h +. margin)
}

// Dodge の疲れ具合に応じた CSS transition (多く逃げるほど遅くなる)
fn dodge_transition(dodge_count: Int) -> String {
  case dodge_count >= 7 {
    True -> "left 1.2s ease-out, top 1.2s ease-out"
    False ->
      case dodge_count >= 5 {
        True -> "left 0.7s ease-out, top 0.7s ease-out"
        False ->
          case dodge_count >= 3 {
            True -> "left 0.45s ease-out, top 0.45s ease-out"
            False -> "left 0.25s ease-out, top 0.25s ease-out"
          }
      }
  }
}

// 逃げ回数に応じた吹き出しテキスト (Dodge 用)
fn dodge_dialogue(count: Int) -> String {
  case count {
    1 -> "えっ……にょわ……"
    2 -> "ちょっと待って……"
    3 -> "まだ仕事中なんで……"
    4 -> "もうちょっとだけ……"
    5 -> "にょわにょわ……！"
    6 -> "つかれてきた……にょわ……"
    _ -> "も、もう限界……にょわ……"
  }
}

// Excuse の言い訳テキスト (index 0 〜 2)
pub fn excuse_text(index: Int) -> String {
  case index {
    0 -> "今休憩中"
    1 -> "17時回ったんで"
    _ -> "システム障害（嘘）"
  }
}

// Clone リストから index 番目の要素を取得
fn clone_at(clones: List(CloneButton), index: Int) -> Result(CloneButton, Nil) {
  case index, clones {
    _, [] -> Error(Nil)
    0, [head, ..] -> Ok(head)
    n, [_, ..tail] -> clone_at(tail, n - 1)
  }
}

// Clone リストから index 番目の要素を削除
fn remove_at_index(clones: List(CloneButton), index: Int) -> List(CloneButton) {
  case index, clones {
    _, [] -> []
    0, [_, ..tail] -> tail
    n, [head, ..tail] -> [head, ..remove_at_index(tail, n - 1)]
  }
}

// Phase 1 〜 3 で使う固定おみくじ (Phase 4 で機嫌ベースに差し替え)
fn placeholder_fortune() -> Fortune {
  Fortune(rank: "めんどくさいから大吉", message: "まあ、せっかく来てくれたんだし……はい、これ。", mood: Neutral)
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

pub fn view(model: Model) -> Element(Msg) {
  html.main(
    [
      attribute.class(
        "min-h-dvh bg-cream font-sans text-[#4A4A4A] flex flex-col items-center justify-center gap-8 px-4 py-12 overflow-hidden",
      ),
    ],
    [
      header_view(),
      character_view(model),
      dialogue_view(model),
      button_view(model),
      result_view(model),
    ],
  )
}

fn header_view() -> Element(Msg) {
  html.header([attribute.class("text-center")], [
    html.h1(
      [
        attribute.class(
          "text-4xl font-bold tracking-wider mb-2 bg-gradient-to-r from-pink to-lavender bg-clip-text text-transparent",
        ),
      ],
      [html.text("にょわくじ2026")],
    ),
    html.p([attribute.class("text-sm text-[#9B9B9B] tracking-wide")], [
      html.text("〜 おみくじ、にょわ〜っと 〜"),
    ]),
  ])
}

fn character_view(model: Model) -> Element(Msg) {
  let #(char_text, anim_class) = case model.phase {
    Idle -> #("（ ˘ω˘ ）", "animate-float")
    Evading(Cooperating) -> #("（ ˘ω˘ ）", "animate-float")
    Evading(_) -> #("（ >ω< ）", "animate-shake")
    Caught -> #("（ ＞ω＜）！", "animate-shake")
    ShowResult(_) -> #("（ ^ω^ ）", "")
    _ -> #("（ ˘ω˘ ）", "animate-float")
  }
  html.div([attribute.class("text-5xl leading-none " <> anim_class)], [
    html.text(char_text),
  ])
}

fn dialogue_view(model: Model) -> Element(Msg) {
  let text = case model.dialogue {
    Some(t) -> t
    None ->
      case model.phase {
        Idle -> "くじ……？にょわ〜……"
        _ -> ""
      }
  }
  case text {
    "" -> html.div([], [])
    _ ->
      html.div(
        [
          attribute.class(
            "bg-white rounded-2xl px-5 py-3 shadow text-sm text-[#4A4A4A] max-w-xs text-center animate-fade-in",
          ),
        ],
        [html.text("💬 " <> text)],
      )
  }
}

fn button_view(model: Model) -> Element(Msg) {
  // 通常ボタンの属性 (Idle / Cooperate 共通)
  let normal_btn_class =
    "px-10 py-4 rounded-full bg-gradient-to-r from-pink to-lavender text-white font-bold text-lg shadow-lg hover:scale-105 active:scale-95 transition-all duration-200 cursor-pointer"

  // Dodge / Clone 用: fixed ポジション固定ボタンの共通スタイル
  let fixed_btn_class =
    "px-10 py-4 rounded-full bg-gradient-to-r from-pink to-lavender text-white font-bold text-lg shadow-lg cursor-pointer"

  // レイアウト崩れを防ぐ透明プレースホルダー
  let placeholder =
    html.div([attribute.class("h-14 w-48 opacity-0 pointer-events-none")], [])

  case model.phase {
    ShowResult(_) -> html.div([], [])

    // ――― Dodge: fixed ポジションで逃げ回る ―――
    Evading(Dodging(pos, count)) -> {
      let x = int.to_string(float.round(pos.x))
      let y = int.to_string(float.round(pos.y))
      let transition = dodge_transition(count)
      html.div([], [
        placeholder,
        html.button(
          [
            attribute.class(fixed_btn_class),
            attribute.style("position", "fixed"),
            attribute.style("left", x <> "px"),
            attribute.style("top", y <> "px"),
            attribute.style("transition", transition),
            attribute.style("z-index", "50"),
            event.on_click(ButtonClicked(0)),
            event.on("mouseenter", decode.success(ButtonHovered)),
            event.on("touchstart", decode.success(ButtonTouched)),
          ],
          [html.text("くじを引く")],
        ),
      ])
    }

    // ――― Clone: 残っている分身ボタンを表示 (外れを押すたびに減る) ―――
    Evading(Cloning(clones)) ->
      html.div([], [placeholder, ..render_clones(clones, 0, fixed_btn_class)])

    // ――― Excuse: disabled ボタン (言い訳は吹き出しに表示 / ボタンは固定テキスト) ―――
    Evading(Excusing(_, _)) ->
      html.button(
        [
          attribute.class(
            "px-10 py-4 rounded-full bg-gradient-to-r from-[#C8C8C8] to-[#D8D8D8] text-white font-bold text-lg shadow cursor-not-allowed opacity-70",
          ),
          attribute.disabled(True),
        ],
        [html.text("くじを引く")],
      )

    // ――― Camo: ランダム位置に fixed で配置しつつ背景色に擬態 ―――
    Evading(Camouflaging(pos)) -> {
      let x = int.to_string(float.round(pos.x))
      let y = int.to_string(float.round(pos.y))
      html.div([], [
        placeholder,
        html.button(
          [
            attribute.class(
              "px-10 py-4 rounded-full font-bold text-lg cursor-pointer border-2",
            ),
            attribute.style("position", "fixed"),
            attribute.style("left", x <> "px"),
            attribute.style("top", y <> "px"),
            attribute.style("z-index", "50"),
            attribute.style("background-color", "var(--color-cream)"),
            attribute.style("color", "var(--color-cream)"),
            attribute.style("border-color", "var(--color-cream-dark)"),
            event.on_click(ButtonClicked(0)),
          ],
          [html.text("くじを引く")],
        ),
      ])
    }

    // ――― Cooperate: 素直にそのまま押せる ―――
    Evading(Cooperating) ->
      html.button(
        [
          attribute.class(normal_btn_class),
          event.on_click(ButtonClicked(0)),
        ],
        [html.text("くじを引く")],
      )

    // ――― Idle / その他: 通常ボタン (ホバーで逃げる) ―――
    _ ->
      html.button(
        [
          attribute.class(normal_btn_class),
          event.on_click(ButtonClicked(0)),
          event.on("mouseenter", decode.success(ButtonHovered)),
          event.on("touchstart", decode.success(ButtonTouched)),
        ],
        [html.text("くじを引く")],
      )
  }
}

// Clone リスト全体を再帰的にレンダリング (残像が消えた後も対応)
fn render_clones(
  clones: List(CloneButton),
  index: Int,
  class: String,
) -> List(Element(Msg)) {
  case clones {
    [] -> []
    [head, ..tail] -> [
      render_clone_button(head, index, class),
      ..render_clones(tail, index + 1, class)
    ]
  }
}

// Clone ボタン 1 つをレンダリング
fn render_clone_button(
  clone: CloneButton,
  index: Int,
  class: String,
) -> Element(Msg) {
  let x = int.to_string(float.round(clone.pos.x))
  let y = int.to_string(float.round(clone.pos.y))
  html.button(
    [
      attribute.class(class),
      attribute.style("position", "fixed"),
      attribute.style("left", x <> "px"),
      attribute.style("top", y <> "px"),
      attribute.style("z-index", "50"),
      attribute.style("transition", "opacity 0.2s ease"),
      event.on_click(ButtonClicked(index)),
    ],
    [html.text("くじを引く")],
  )
}

fn result_view(model: Model) -> Element(Msg) {
  case model.phase {
    ShowResult(fortune) ->
      html.div(
        [attribute.class("flex flex-col items-center gap-5 animate-fade-in")],
        [
          html.div(
            [
              attribute.class(
                "bg-white rounded-3xl px-10 py-8 shadow-xl text-center max-w-sm w-full",
              ),
            ],
            [
              html.p(
                [
                  attribute.class(
                    "text-2xl font-bold bg-gradient-to-r from-pink to-lavender bg-clip-text text-transparent mb-3",
                  ),
                ],
                [html.text(fortune.rank)],
              ),
              html.p(
                [attribute.class("text-[#4A4A4A] text-sm leading-relaxed")],
                [html.text(fortune.message)],
              ),
            ],
          ),
          html.button(
            [
              attribute.class(
                "text-sm text-[#9B9B9B] underline underline-offset-2 hover:text-pink transition-colors duration-200 cursor-pointer",
              ),
              event.on_click(PlayAgain),
            ],
            [html.text("もう一回にょわる")],
          ),
        ],
      )
    _ -> html.div([], [])
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// ---------------------------------------------------------------------------
// Effects / FFI wrappers
// ---------------------------------------------------------------------------

fn get_timestamp() -> effect.Effect(Msg) {
  effect.from(fn(dispatch) { dispatch(GotTimestamp(now())) })
}

fn delay_msg(msg: Msg, ms: Int) -> effect.Effect(Msg) {
  effect.from(fn(dispatch) { set_timeout(fn() { dispatch(msg) }, ms) })
}

@external(javascript, "./nyowa_ffi.mjs", "setTimeoutFn")
fn set_timeout(callback: fn() -> Nil, ms: Int) -> Nil

@external(javascript, "./nyowa_ffi.mjs", "now")
fn now() -> Float

@external(javascript, "./nyowa_ffi.mjs", "random")
pub fn random() -> Float

@external(javascript, "./nyowa_ffi.mjs", "getViewportSize")
pub fn get_viewport_size() -> #(Float, Float)
