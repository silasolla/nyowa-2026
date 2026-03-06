import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import nyowa

pub fn main() -> Nil {
  gleeunit.main()
}

// --- init ---

pub fn init_phase_is_idle_test() {
  let #(model, _) = nyowa.init(Nil)
  model.phase |> should.equal(nyowa.Idle)
}

pub fn init_evade_count_is_zero_test() {
  let #(model, _) = nyowa.init(Nil)
  model.evade_count |> should.equal(0)
}

pub fn init_first_interact_at_is_none_test() {
  let #(model, _) = nyowa.init(Nil)
  model.first_interact_at |> should.equal(None)
}

// --- update: GotTimestamp ---

pub fn got_timestamp_sets_page_loaded_at_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.GotTimestamp(1_234_567.0))
  updated.page_loaded_at |> should.equal(1_234_567.0)
}

// --- update: ButtonClicked ---

pub fn button_clicked_while_idle_transitions_to_show_result_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonClicked(0))
  case updated.phase {
    nyowa.ShowResult(_) -> Nil
    _ -> should.fail()
  }
}

pub fn button_clicked_records_first_interact_at_test() {
  let #(model, _) = nyowa.init(Nil)
  let with_ts = nyowa.update(model, nyowa.GotTimestamp(9999.0)).0
  let #(updated, _) = nyowa.update(with_ts, nyowa.ButtonClicked(0))
  updated.first_interact_at |> should.equal(Some(9999.0))
}

pub fn button_clicked_while_evading_is_ignored_test() {
  let #(model, _) = nyowa.init(Nil)
  let evading =
    nyowa.Model(
      ..model,
      phase: nyowa.Evading(nyowa.Dodging(
        pos: nyowa.Position(100.0, 100.0),
        evade_count: 1,
      )),
    )
  let #(updated, _) = nyowa.update(evading, nyowa.ButtonClicked(0))
  updated.phase |> should.equal(evading.phase)
}

// --- update: PlayAgain ---

pub fn play_again_resets_to_idle_test() {
  let #(model, _) = nyowa.init(Nil)
  let in_result =
    nyowa.Model(
      ..model,
      phase: nyowa.ShowResult(nyowa.Fortune(
        rank: "大吉",
        message: "テスト",
        mood: nyowa.Neutral,
      )),
      evade_count: 3,
    )
  let #(updated, _) = nyowa.update(in_result, nyowa.PlayAgain)
  updated.phase |> should.equal(nyowa.Idle)
  updated.evade_count |> should.equal(0)
}

pub fn play_again_clears_first_interact_at_test() {
  let #(model, _) = nyowa.init(Nil)
  let with_interact = nyowa.Model(..model, first_interact_at: Some(12_345.0))
  let #(updated, _) = nyowa.update(with_interact, nyowa.PlayAgain)
  updated.first_interact_at |> should.equal(None)
}
