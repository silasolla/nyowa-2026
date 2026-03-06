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
  )
}

pub type Msg {
  ButtonHovered
  ButtonTouched
  ButtonClicked(index: Int)
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
      viewport: #(375.0, 812.0),
      dialogue: None,
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

    ButtonClicked(_index) ->
      case model.phase {
        // 抵抗中はゴーストクリックなどを無視 (Phase 2 以降で有効活用)
        Evading(_) -> #(model, effect.none())
        Idle -> {
          // Phase 1: 固定おみくじを即時表示 (Phase 4 で機嫌・乱数に基づく選択に差し替え）
          let fortune =
            Fortune(
              rank: "めんどくさいから大吉",
              message: "まあ、せっかく来てくれたんだし……はい、これ。",
              mood: Neutral,
            )
          #(
            Model(
              ..model,
              phase: ShowResult(fortune),
              first_interact_at: Some(model.page_loaded_at),
            ),
            effect.none(),
          )
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
      ),
      effect.none(),
    )

    // Phase 2 以降で実装するメッセージ
    ButtonHovered | ButtonTouched -> #(model, effect.none())
    ExcuseExpired -> #(model, effect.none())
    DrawTick -> #(model, effect.none())
    DrawInterruption(_) -> #(model, effect.none())
    DrawComplete(_) -> #(model, effect.none())
    TransitionDone -> #(model, effect.none())
    GotRandom(_) -> #(model, effect.none())
  }
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
    Caught -> #("（ ＞ω＜）！", "animate-shake")
    ShowResult(_) -> #("（ ^ω^ ）", "")
    _ -> #("（ ˘ω˘ ）", "animate-float")
  }
  html.div([attribute.class("text-5xl leading-none " <> anim_class)], [
    html.text(char_text),
  ])
}

fn dialogue_view(model: Model) -> Element(Msg) {
  let text = case model.phase {
    Idle -> "くじ……？にょわ〜……"
    Caught -> "えっ……つかまった……"
    _ -> ""
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
  case model.phase {
    ShowResult(_) -> html.div([], [])
    _ ->
      html.button(
        [
          attribute.class(
            "px-10 py-4 rounded-full bg-gradient-to-r from-pink to-lavender text-white font-bold text-lg shadow-lg hover:scale-105 active:scale-95 transition-all duration-200 cursor-pointer",
          ),
          event.on_click(ButtonClicked(0)),
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
// Effects (FFI wrappers)
// ---------------------------------------------------------------------------

fn get_timestamp() -> effect.Effect(Msg) {
  effect.from(fn(dispatch) { dispatch(GotTimestamp(now())) })
}

@external(javascript, "./nyowa_ffi.mjs", "setTimeoutFn")
pub fn set_timeout(callback: fn() -> Nil, ms: Int) -> Nil

@external(javascript, "./nyowa_ffi.mjs", "now")
fn now() -> Float

@external(javascript, "./nyowa_ffi.mjs", "random")
pub fn random() -> Float

@external(javascript, "./nyowa_ffi.mjs", "getViewportSize")
pub fn get_viewport_size() -> #(Float, Float)
