import gleam/option.{type Option}

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
  Drawing(state: DrawState)
  ShowResult(fortune: Fortune)
}

pub type Model {
  Model(
    phase: Phase,
    idle_started_at: Float,
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
  DrawInterruption(DrawState)
  DrawComplete(Fortune)
  PlayAgain
  ClearDialogue
}
