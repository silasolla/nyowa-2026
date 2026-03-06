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
  Camouflaging
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

    // PC: マウスホバー → Dodge 発動
    ButtonHovered -> handle_evasion(model, False)

    // モバイル: タッチ開始 → Dodge 発動 + ゴーストクリック防止タイマー起動
    ButtonTouched -> handle_evasion(model, True)

    GhostClickExpired -> #(
      Model(..model, recently_touched: False),
      effect.none(),
    )

    ButtonClicked(_index) ->
      case model.phase {
        // 逃げている最中かつゴーストクリック猶予中は無視
        Evading(Dodging(_, _)) ->
          case model.recently_touched {
            True -> #(model, effect.none())
            False ->
              // ボタンを捕まえた
              #(
                Model(
                  ..model,
                  phase: ShowResult(placeholder_fortune()),
                  first_interact_at: Some(model.page_loaded_at),
                ),
                effect.none(),
              )
          }
        // Phase 3 以降で実装する他の逃げパターン中はまだ無視
        Evading(_) -> #(model, effect.none())
        // Idle 時はホバー前に直クリックされた場合 (レア)
        Idle -> #(
          Model(
            ..model,
            phase: ShowResult(placeholder_fortune()),
            first_interact_at: Some(model.page_loaded_at),
          ),
          effect.none(),
        )
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

    // Phase 3 以降で実装するメッセージ
    ExcuseExpired -> #(model, effect.none())
    DrawTick -> #(model, effect.none())
    DrawInterruption(_) -> #(model, effect.none())
    DrawComplete(_) -> #(model, effect.none())
    TransitionDone -> #(model, effect.none())
    GotRandom(_) -> #(model, effect.none())
  }
}

// Dodge 共通ロジック (PC ホバー・モバイルタッチ共用)
fn handle_evasion(model: Model, is_touch: Bool) -> #(Model, effect.Effect(Msg)) {
  case model.phase {
    Idle | Evading(Dodging(_, _)) -> {
      let new_evade_count = model.evade_count + 1
      let new_dodge_count = case model.phase {
        Evading(Dodging(_, c)) -> c + 1
        _ -> 1
      }
      let pos = random_pos(model.viewport)
      let new_phase = Evading(Dodging(pos: pos, evade_count: new_dodge_count))
      let eff = case is_touch {
        True -> delay_msg(GhostClickExpired, 500)
        False -> effect.none()
      }
      #(
        Model(
          ..model,
          phase: new_phase,
          evade_count: new_evade_count,
          dialogue: Some(dodge_dialogue(new_evade_count)),
          recently_touched: is_touch,
        ),
        eff,
      )
    }
    _ -> #(model, effect.none())
  }
}

// ランダム位置を生成 (ビューポート内に収める)
fn random_pos(viewport: #(Float, Float)) -> Position {
  let #(vp_w, vp_h) = viewport
  let btn_w = 220.0
  let btn_h = 64.0
  let margin = 24.0
  let usable_w = float.max(vp_w -. btn_w -. margin *. 2.0, 0.0)
  let usable_h = float.max(vp_h -. btn_h -. margin *. 2.0, 0.0)
  Position(x: random() *. usable_w +. margin, y: random() *. usable_h +. margin)
}

// 逃げ回数に応じた吹き出しテキスト
fn dodge_dialogue(count: Int) -> String {
  case count {
    1 -> "えっ……にょわ……"
    2 -> "ちょっと待って……"
    3 -> "まだ仕事中なんで……"
    4 -> "もうちょっとだけ……"
    5 -> "にょわにょわ……！"
    _ -> "も、もう限界……にょわ……"
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
  let common_attrs = [
    event.on_click(ButtonClicked(0)),
    event.on("mouseenter", decode.success(ButtonHovered)),
    event.on("touchstart", decode.success(ButtonTouched)),
  ]
  case model.phase {
    ShowResult(_) -> html.div([], [])
    Evading(Dodging(pos, _)) -> {
      // 通常フローに空のプレースホルダーを残しつつ
      // 本体ボタンを fixed で自由に動かす
      let x = int.to_string(float.round(pos.x))
      let y = int.to_string(float.round(pos.y))
      html.div([], [
        html.div(
          [attribute.class("h-14 w-48 opacity-0 pointer-events-none")],
          [],
        ),
        html.button(
          [
            attribute.class(
              "px-10 py-4 rounded-full bg-gradient-to-r from-pink to-lavender text-white font-bold text-lg shadow-lg cursor-pointer",
            ),
            attribute.style("position", "fixed"),
            attribute.style("left", x <> "px"),
            attribute.style("top", y <> "px"),
            attribute.style(
              "transition",
              "left 0.25s ease-out, top 0.25s ease-out",
            ),
            attribute.style("z-index", "50"),
            ..common_attrs
          ],
          [html.text("くじを引く")],
        ),
      ])
    }
    _ ->
      html.button(
        [
          attribute.class(
            "px-10 py-4 rounded-full bg-gradient-to-r from-pink to-lavender text-white font-bold text-lg shadow-lg hover:scale-105 active:scale-95 transition-all duration-200 cursor-pointer",
          ),
          ..common_attrs
        ],
        [html.text("くじを引く")],
      )
  }
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
