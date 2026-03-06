import lustre
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub type Position {
  Position(x: Float, y: Float)
}

pub type CloneButton {
  CloneButton(pos: Position, is_real: Bool)
}

pub type Fortune {
  Fortune(rank: String, message: String, mood: Mood)
}

pub type Mood {
  Furious
  Grumpy
  Neutral
  Rested
  Sleepy
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
  Result(fortune: Fortune)
}

pub type Model {
  Model(
    phase: Phase,
    page_loaded_at: Float,
    first_interact_at: Result(Float, Nil),
    evade_count: Int,
    viewport: #(Float, Float),
    dialogue: Result(String, Nil),
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
      first_interact_at: Error(Nil),
      evade_count: 0,
      viewport: #(375.0, 812.0),
      dialogue: Error(Nil),
    )
  #(model, get_timestamp())
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    GotTimestamp(ts) -> #(
      Model(..model, page_loaded_at: ts),
      effect.none(),
    )

    GotViewport(w, h) -> #(
      Model(..model, viewport: #(w, h)),
      effect.none(),
    )

    ButtonClicked(_index) ->
      case model.phase {
        // 抵抗中はゴーストクリックなどを無視する
        Evading(_) -> #(model, effect.none())
        Idle -> #(Model(..model, phase: Caught), effect.none())
        _ -> #(model, effect.none())
      }

    PlayAgain -> #(
      Model(
        ..model,
        phase: Idle,
        evade_count: 0,
        dialogue: Error(Nil),
        first_interact_at: Error(Nil),
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
  html.main([], [
    html.h1([], [html.text("にょわくじ2026")]),
    case model.phase {
      Result(fortune) ->
        html.p([], [html.text(fortune.rank <> "　" <> fortune.message)])
      _ -> html.p([], [html.text("(Phase 1 以降で実装)")])
    },
  ])
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
fn set_timeout(callback: fn() -> Nil, ms: Int) -> Nil

@external(javascript, "./nyowa_ffi.mjs", "now")
fn now() -> Float

@external(javascript, "./nyowa_ffi.mjs", "random")
pub fn random() -> Float

@external(javascript, "./nyowa_ffi.mjs", "getViewportSize")
fn get_viewport_size_ffi() -> #(Float, Float)
