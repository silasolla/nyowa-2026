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

// --- update: GotTimestamp ---

pub fn got_timestamp_sets_page_loaded_at_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.GotTimestamp(1_234_567.0))
  updated.page_loaded_at |> should.equal(1_234_567.0)
}

// --- update: ButtonClicked ガード ---

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

pub fn button_clicked_while_idle_transitions_to_caught_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonClicked(0))
  updated.phase |> should.equal(nyowa.Caught)
}

// --- update: PlayAgain ---

pub fn play_again_resets_to_idle_test() {
  let #(model, _) = nyowa.init(Nil)
  let in_result =
    nyowa.Model(
      ..model,
      phase: nyowa.Result(nyowa.Fortune(
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
