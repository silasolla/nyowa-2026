import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import nyowa

pub fn main() -> Nil {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// init
// ---------------------------------------------------------------------------

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

pub fn init_recently_touched_is_false_test() {
  let #(model, _) = nyowa.init(Nil)
  model.recently_touched |> should.equal(False)
}

// ---------------------------------------------------------------------------
// GotTimestamp
// ---------------------------------------------------------------------------

pub fn got_timestamp_sets_page_loaded_at_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.GotTimestamp(1_234_567.0))
  updated.page_loaded_at |> should.equal(1_234_567.0)
}

// ---------------------------------------------------------------------------
// ButtonHovered — Dodge 発動
// ---------------------------------------------------------------------------

pub fn button_hovered_while_idle_starts_dodging_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonHovered)
  case updated.phase {
    nyowa.Evading(nyowa.Dodging(_, count)) -> count |> should.equal(1)
    _ -> should.fail()
  }
}

pub fn button_hovered_increments_evade_count_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonHovered)
  updated.evade_count |> should.equal(1)
}

pub fn button_hovered_sets_dialogue_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonHovered)
  case updated.dialogue {
    Some(_) -> Nil
    None -> should.fail()
  }
}

pub fn button_hovered_again_increments_count_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(m1, _) = nyowa.update(model, nyowa.ButtonHovered)
  let #(m2, _) = nyowa.update(m1, nyowa.ButtonHovered)
  case m2.phase {
    nyowa.Evading(nyowa.Dodging(_, count)) -> count |> should.equal(2)
    _ -> should.fail()
  }
  m2.evade_count |> should.equal(2)
}

pub fn button_hovered_does_not_set_recently_touched_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonHovered)
  updated.recently_touched |> should.equal(False)
}

// ---------------------------------------------------------------------------
// ButtonTouched — モバイル Dodge + ゴーストクリック防止
// ---------------------------------------------------------------------------

pub fn button_touched_starts_dodging_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonTouched)
  case updated.phase {
    nyowa.Evading(nyowa.Dodging(_, _)) -> Nil
    _ -> should.fail()
  }
}

pub fn button_touched_sets_recently_touched_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonTouched)
  updated.recently_touched |> should.equal(True)
}

// ---------------------------------------------------------------------------
// GhostClickExpired — ゴーストクリック猶予終了
// ---------------------------------------------------------------------------

pub fn ghost_click_expired_clears_recently_touched_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(touched, _) = nyowa.update(model, nyowa.ButtonTouched)
  touched.recently_touched |> should.equal(True)
  let #(cleared, _) = nyowa.update(touched, nyowa.GhostClickExpired)
  cleared.recently_touched |> should.equal(False)
}

// ---------------------------------------------------------------------------
// ButtonClicked — Dodge 中のキャッチ・ガード
// ---------------------------------------------------------------------------

pub fn button_clicked_while_dodging_and_not_recently_touched_catches_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(dodging, _) = nyowa.update(model, nyowa.ButtonHovered)
  let #(updated, _) = nyowa.update(dodging, nyowa.ButtonClicked(0))
  case updated.phase {
    nyowa.ShowResult(_) -> Nil
    _ -> should.fail()
  }
}

pub fn button_clicked_while_dodging_and_recently_touched_is_ignored_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(dodging, _) = nyowa.update(model, nyowa.ButtonTouched)
  dodging.recently_touched |> should.equal(True)
  let #(updated, _) = nyowa.update(dodging, nyowa.ButtonClicked(0))
  // ゴーストクリックなので phase は変わらない
  updated.phase |> should.equal(dodging.phase)
}

pub fn button_clicked_while_idle_goes_to_result_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonClicked(0))
  case updated.phase {
    nyowa.ShowResult(_) -> Nil
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// PlayAgain — リセット
// ---------------------------------------------------------------------------

pub fn play_again_resets_to_idle_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(m1, _) = nyowa.update(model, nyowa.ButtonHovered)
  let #(m2, _) = nyowa.update(m1, nyowa.ButtonClicked(0))
  let #(reset, _) = nyowa.update(m2, nyowa.PlayAgain)
  reset.phase |> should.equal(nyowa.Idle)
  reset.evade_count |> should.equal(0)
  reset.recently_touched |> should.equal(False)
  reset.first_interact_at |> should.equal(None)
}
