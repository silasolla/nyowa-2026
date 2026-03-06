import gleam/float
import lustre/effect
import nyowa/content
import nyowa/ffi
import nyowa/model.{type CloneButton, type EvasionState, type Msg, type Position}

pub fn select_evasion_pattern(
  rand: Float,
  viewport: #(Float, Float),
) -> #(EvasionState, String, effect.Effect(Msg)) {
  case rand <. 0.3 {
    True -> {
      let pos = random_pos(viewport)
      #(
        model.Dodging(pos: pos, evade_count: 1),
        content.dodge_initial,
        effect.none(),
      )
    }
    False ->
      case rand <. 0.5 {
        True -> {
          let clones = generate_clones(viewport)
          #(model.Cloning(clones: clones), content.clone_initial, effect.none())
        }
        False ->
          case rand <. 0.7 {
            True -> {
              let text = content.excuse_text(0)
              #(
                model.Excusing(index: 0, text: text),
                text,
                ffi.delay_msg(model.ExcuseExpired, 2500),
              )
            }
            False ->
              case rand <. 0.85 {
                True -> {
                  let pos = random_pos(viewport)
                  #(
                    model.Camouflaging(pos: pos),
                    content.camo_initial,
                    effect.none(),
                  )
                }
                False -> #(
                  model.Cooperating,
                  content.cooperate_initial,
                  effect.none(),
                )
              }
          }
      }
  }
}

pub fn generate_clones(viewport: #(Float, Float)) -> List(CloneButton) {
  let real_idx = float.round(ffi.random() *. 2.0)
  let p0 = random_pos(viewport)
  let p1 = random_pos(viewport)
  let p2 = random_pos(viewport)
  [
    model.CloneButton(pos: p0, is_real: real_idx == 0),
    model.CloneButton(pos: p1, is_real: real_idx == 1),
    model.CloneButton(pos: p2, is_real: real_idx == 2),
  ]
}

pub fn random_pos(viewport: #(Float, Float)) -> Position {
  let #(vp_w, vp_h) = viewport
  let btn_w = 220.0
  let btn_h = 64.0
  let margin = 24.0
  let usable_w = float.max(vp_w -. btn_w -. margin *. 2.0, 0.0)
  let usable_h = float.max(vp_h -. btn_h -. margin *. 2.0, 0.0)
  model.Position(
    x: ffi.random() *. usable_w +. margin,
    y: ffi.random() *. usable_h +. margin,
  )
}

pub fn dodge_transition(dodge_count: Int) -> String {
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

pub fn clone_at(
  clones: List(CloneButton),
  index: Int,
) -> Result(CloneButton, Nil) {
  case index, clones {
    _, [] -> Error(Nil)
    0, [head, ..] -> Ok(head)
    n, [_, ..tail] -> clone_at(tail, n - 1)
  }
}

pub fn remove_at_index(
  clones: List(CloneButton),
  index: Int,
) -> List(CloneButton) {
  case index, clones {
    _, [] -> []
    0, [_, ..tail] -> tail
    n, [head, ..tail] -> [head, ..remove_at_index(tail, n - 1)]
  }
}
