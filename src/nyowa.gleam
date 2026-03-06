import gleam/option.{None, Some}
import lustre
import lustre/effect
import nyowa/content
import nyowa/evasion
import nyowa/ffi
import nyowa/fortune
import nyowa/model.{type Model, type Msg}
import nyowa/view

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

pub fn init(_flags: Nil) -> #(Model, effect.Effect(Msg)) {
  let m =
    model.Model(
      phase: model.Idle,
      idle_started_at: ffi.now(),
      first_interact_at: None,
      evade_count: 0,
      viewport: ffi.get_viewport_size(),
      dialogue: None,
      recently_touched: False,
    )
  #(m, effect.none())
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

pub fn update(m: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    model.ButtonHovered -> handle_evasion(m, False)
    model.ButtonTouched -> handle_evasion(m, True)

    model.GhostClickExpired -> #(
      model.Model(..m, recently_touched: False),
      effect.none(),
    )

    model.ButtonClicked(index) ->
      case m.phase {
        model.Evading(model.Dodging(_, _)) ->
          case m.recently_touched {
            True -> #(m, effect.none())
            False -> do_catch(m)
          }

        model.Evading(model.Cloning(clones)) ->
          case evasion.clone_at(clones, index) {
            Ok(model.CloneButton(_, True)) -> do_catch(m)
            Ok(model.CloneButton(_, False)) -> #(
              model.Model(
                ..m,
                phase: model.Evading(
                  model.Cloning(clones: evasion.remove_at_index(clones, index)),
                ),
                evade_count: m.evade_count + 2,
                dialogue: Some(content.clone_fake_hit),
              ),
              effect.none(),
            )
            Error(_) -> #(m, effect.none())
          }

        model.Evading(model.Excusing(_, _)) -> #(m, effect.none())
        model.Evading(model.Camouflaging(_)) -> do_catch(m)
        model.Evading(model.Cooperating) -> do_catch(m)

        model.Idle ->
          do_catch(model.Model(..m, first_interact_at: Some(ffi.now())))

        _ -> #(m, effect.none())
      }

    model.ExcuseExpired ->
      case m.phase {
        model.Evading(model.Excusing(index, _)) ->
          case index >= 2 {
            True -> #(
              model.Model(
                ..m,
                phase: model.Idle,
                evade_count: m.evade_count + 1,
                dialogue: Some(content.excuse_hint),
                recently_touched: False,
                idle_started_at: ffi.now(),
              ),
              ffi.delay_msg(model.ClearDialogue, 4000),
            )
            False -> {
              let next_idx = index + 1
              let next_text = content.excuse_text(next_idx)
              #(
                model.Model(
                  ..m,
                  phase: model.Evading(model.Excusing(
                    index: next_idx,
                    text: next_text,
                  )),
                  dialogue: Some(next_text),
                ),
                ffi.delay_msg(model.ExcuseExpired, 2500),
              )
            }
          }
        _ -> #(m, effect.none())
      }

    model.PlayAgain -> #(
      model.Model(
        ..m,
        phase: model.Idle,
        evade_count: 0,
        dialogue: None,
        first_interact_at: None,
        recently_touched: False,
        idle_started_at: ffi.now(),
      ),
      effect.none(),
    )

    model.ClearDialogue ->
      case m.phase {
        model.Idle -> #(model.Model(..m, dialogue: None), effect.none())
        _ -> #(m, effect.none())
      }

    model.DrawInterruption(new_state) ->
      case m.phase {
        model.Drawing(_) -> {
          let dialogue = case new_state {
            model.Paused -> Some(content.draw_paused)
            model.Reversing -> Some(content.draw_reversing)
            _ -> m.dialogue
          }
          #(
            model.Model(
              ..m,
              phase: model.Drawing(new_state),
              dialogue: dialogue,
            ),
            effect.none(),
          )
        }
        _ -> #(m, effect.none())
      }

    model.DrawComplete(ft) ->
      case m.phase {
        model.Drawing(_) -> #(
          model.Model(..m, phase: model.ShowResult(ft), dialogue: None),
          effect.none(),
        )
        _ -> #(m, effect.none())
      }
  }
}

fn do_catch(m: Model) -> #(Model, effect.Effect(Msg)) {
  let idle_ms = case m.first_interact_at {
    Some(t) -> t -. m.idle_started_at
    None -> 0.0
  }
  let mood = fortune.determine_mood(m.evade_count, idle_ms)
  let ft = fortune.select_fortune(mood, ffi.random())
  let rand = ffi.random()
  case rand <. 0.15 {
    True -> #(
      model.Model(
        ..m,
        phase: model.Drawing(model.Instant),
        dialogue: Some(content.draw_instant),
      ),
      ffi.delay_msg(model.DrawComplete(ft), 900),
    )
    False ->
      case rand <. 0.55 {
        True -> #(
          model.Model(
            ..m,
            phase: model.Drawing(model.Spinning),
            dialogue: Some(content.draw_spinning),
          ),
          ffi.delay_msg(model.DrawComplete(ft), 2800),
        )
        False ->
          case rand <. 0.8 {
            True -> #(
              model.Model(
                ..m,
                phase: model.Drawing(model.Spinning),
                dialogue: Some(content.draw_spinning),
              ),
              effect.batch([
                ffi.delay_msg(model.DrawInterruption(model.Paused), 1200),
                ffi.delay_msg(model.DrawComplete(ft), 3500),
              ]),
            )
            False -> #(
              model.Model(
                ..m,
                phase: model.Drawing(model.Spinning),
                dialogue: Some(content.draw_spinning),
              ),
              effect.batch([
                ffi.delay_msg(model.DrawInterruption(model.Reversing), 1200),
                ffi.delay_msg(model.DrawComplete(ft), 3400),
              ]),
            )
          }
      }
  }
}

fn handle_evasion(m: Model, is_touch: Bool) -> #(Model, effect.Effect(Msg)) {
  let touch_eff = case is_touch {
    True -> ffi.delay_msg(model.GhostClickExpired, 500)
    False -> effect.none()
  }
  case m.phase {
    model.Idle -> {
      let rand = ffi.random()
      let interact_time = ffi.now()
      let #(state, dialogue_text, pattern_eff) =
        evasion.select_evasion_pattern(rand, m.viewport)
      #(
        model.Model(
          ..m,
          phase: model.Evading(state),
          recently_touched: is_touch,
          dialogue: Some(dialogue_text),
          first_interact_at: Some(interact_time),
        ),
        effect.batch([pattern_eff, touch_eff]),
      )
    }

    model.Evading(model.Dodging(_, count)) -> {
      let new_evade_count = m.evade_count + 1
      let next_count = count + 1
      let pos = evasion.random_pos(m.viewport)
      #(
        model.Model(
          ..m,
          phase: model.Evading(model.Dodging(pos: pos, evade_count: next_count)),
          evade_count: new_evade_count,
          dialogue: Some(content.dodge_dialogue(next_count)),
          recently_touched: is_touch,
        ),
        touch_eff,
      )
    }

    _ -> #(m, effect.none())
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view.view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
