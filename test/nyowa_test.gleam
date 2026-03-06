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
// ButtonHovered — パターン選択
// ---------------------------------------------------------------------------

pub fn button_hovered_from_idle_starts_evading_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonHovered)
  case updated.phase {
    nyowa.Evading(_) -> Nil
    _ -> should.fail()
  }
}

pub fn button_hovered_increments_evade_count_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonHovered)
  updated.evade_count |> should.equal(1)
}

pub fn button_hovered_sets_first_interact_at_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(m1, _) = nyowa.update(model, nyowa.GotTimestamp(5000.0))
  let #(m2, _) = nyowa.update(m1, nyowa.ButtonHovered)
  m2.first_interact_at |> should.equal(Some(5000.0))
}

pub fn button_hovered_sets_dialogue_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonHovered)
  case updated.dialogue {
    Some(_) -> Nil
    None -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Dodge パターン
// ---------------------------------------------------------------------------

pub fn dodge_hovered_again_increments_count_test() {
  let #(model, _) = nyowa.init(Nil)
  // Dodge 状態を手動で作成
  let dodging_model =
    nyowa.Model(
      ..model,
      phase: nyowa.Evading(nyowa.Dodging(
        pos: nyowa.Position(100.0, 100.0),
        evade_count: 2,
      )),
      evade_count: 2,
    )
  let #(updated, _) = nyowa.update(dodging_model, nyowa.ButtonHovered)
  case updated.phase {
    nyowa.Evading(nyowa.Dodging(_, count)) -> count |> should.equal(3)
    _ -> should.fail()
  }
  updated.evade_count |> should.equal(3)
}

pub fn dodge_click_not_recently_touched_catches_test() {
  let #(model, _) = nyowa.init(Nil)
  let dodging =
    nyowa.Model(
      ..model,
      phase: nyowa.Evading(nyowa.Dodging(
        pos: nyowa.Position(100.0, 100.0),
        evade_count: 1,
      )),
      recently_touched: False,
    )
  let #(updated, _) = nyowa.update(dodging, nyowa.ButtonClicked(0))
  case updated.phase {
    nyowa.ShowResult(_) -> Nil
    _ -> should.fail()
  }
}

pub fn dodge_click_recently_touched_is_ignored_test() {
  let #(model, _) = nyowa.init(Nil)
  let dodging =
    nyowa.Model(
      ..model,
      phase: nyowa.Evading(nyowa.Dodging(
        pos: nyowa.Position(100.0, 100.0),
        evade_count: 1,
      )),
      recently_touched: True,
    )
  let #(updated, _) = nyowa.update(dodging, nyowa.ButtonClicked(0))
  updated.phase |> should.equal(dodging.phase)
}

// ---------------------------------------------------------------------------
// Clone パターン
// ---------------------------------------------------------------------------

pub fn clone_real_button_clicked_catches_test() {
  let #(model, _) = nyowa.init(Nil)
  let clones = [
    nyowa.CloneButton(pos: nyowa.Position(0.0, 0.0), is_real: False),
    nyowa.CloneButton(pos: nyowa.Position(100.0, 0.0), is_real: True),
    nyowa.CloneButton(pos: nyowa.Position(200.0, 0.0), is_real: False),
  ]
  let cloning =
    nyowa.Model(..model, phase: nyowa.Evading(nyowa.Cloning(clones: clones)))
  let #(updated, _) = nyowa.update(cloning, nyowa.ButtonClicked(1))
  case updated.phase {
    nyowa.ShowResult(_) -> Nil
    _ -> should.fail()
  }
}

pub fn clone_fake_button_clicked_removes_it_test() {
  let #(model, _) = nyowa.init(Nil)
  let fake0 = nyowa.CloneButton(pos: nyowa.Position(0.0, 0.0), is_real: False)
  let real1 = nyowa.CloneButton(pos: nyowa.Position(100.0, 0.0), is_real: True)
  let fake2 =
    nyowa.CloneButton(pos: nyowa.Position(200.0, 0.0), is_real: False)
  let cloning =
    nyowa.Model(
      ..model,
      phase: nyowa.Evading(nyowa.Cloning(clones: [fake0, real1, fake2])),
      evade_count: 1,
    )
  let #(updated, _) = nyowa.update(cloning, nyowa.ButtonClicked(0))
  // index 0 の残像が消えて 2 つになる
  updated.phase
  |> should.equal(nyowa.Evading(nyowa.Cloning(clones: [real1, fake2])))
  // evade_count が加算される
  updated.evade_count |> should.equal(2)
  // エラーダイアログが出る
  updated.dialogue |> should.equal(Some("それ残像です……"))
}

// ---------------------------------------------------------------------------
// Excuse パターン
// ---------------------------------------------------------------------------

pub fn excuse_expired_low_index_advances_to_next_test() {
  let #(model, _) = nyowa.init(Nil)
  let excusing =
    nyowa.Model(
      ..model,
      phase: nyowa.Evading(nyowa.Excusing(index: 0, text: "今休憩中")),
    )
  let #(updated, _) = nyowa.update(excusing, nyowa.ExcuseExpired)
  case updated.phase {
    nyowa.Evading(nyowa.Excusing(index: 1, text: _)) -> Nil
    _ -> should.fail()
  }
  updated.evade_count |> should.equal(1)
}

pub fn excuse_expired_high_index_resets_to_idle_test() {
  let #(model, _) = nyowa.init(Nil)
  let excusing =
    nyowa.Model(
      ..model,
      phase: nyowa.Evading(nyowa.Excusing(index: 2, text: "システム障害（嘘）")),
    )
  let #(updated, _) = nyowa.update(excusing, nyowa.ExcuseExpired)
  updated.phase |> should.equal(nyowa.Idle)
  updated.dialogue |> should.equal(None)
}

pub fn excuse_button_click_is_ignored_test() {
  let #(model, _) = nyowa.init(Nil)
  let excusing =
    nyowa.Model(
      ..model,
      phase: nyowa.Evading(nyowa.Excusing(index: 0, text: "今休憩中")),
    )
  let #(updated, _) = nyowa.update(excusing, nyowa.ButtonClicked(0))
  updated.phase |> should.equal(excusing.phase)
}

// ---------------------------------------------------------------------------
// Camo パターン
// ---------------------------------------------------------------------------

pub fn camo_button_click_catches_test() {
  let #(model, _) = nyowa.init(Nil)
  let camo =
    nyowa.Model(
      ..model,
      phase: nyowa.Evading(
        nyowa.Camouflaging(pos: nyowa.Position(100.0, 200.0)),
      ),
    )
  let #(updated, _) = nyowa.update(camo, nyowa.ButtonClicked(0))
  case updated.phase {
    nyowa.ShowResult(_) -> Nil
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Cooperate パターン
// ---------------------------------------------------------------------------

pub fn cooperate_button_click_catches_test() {
  let #(model, _) = nyowa.init(Nil)
  let coop = nyowa.Model(..model, phase: nyowa.Evading(nyowa.Cooperating))
  let #(updated, _) = nyowa.update(coop, nyowa.ButtonClicked(0))
  case updated.phase {
    nyowa.ShowResult(_) -> Nil
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// GhostClickExpired
// ---------------------------------------------------------------------------

pub fn ghost_click_expired_clears_flag_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(touched, _) = nyowa.update(model, nyowa.ButtonTouched)
  touched.recently_touched |> should.equal(True)
  let #(cleared, _) = nyowa.update(touched, nyowa.GhostClickExpired)
  cleared.recently_touched |> should.equal(False)
}

// ---------------------------------------------------------------------------
// PlayAgain
// ---------------------------------------------------------------------------

pub fn play_again_full_reset_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(m1, _) = nyowa.update(model, nyowa.ButtonHovered)
  let #(m2, _) = nyowa.update(m1, nyowa.ButtonClicked(0))
  let #(reset, _) = nyowa.update(m2, nyowa.PlayAgain)
  reset.phase |> should.equal(nyowa.Idle)
  reset.evade_count |> should.equal(0)
  reset.recently_touched |> should.equal(False)
  reset.first_interact_at |> should.equal(None)
  reset.dialogue |> should.equal(None)
}

// ---------------------------------------------------------------------------
// excuse_text ユーティリティ
// ---------------------------------------------------------------------------

pub fn excuse_text_index_0_test() {
  nyowa.excuse_text(0) |> should.equal("今休憩中")
}

pub fn excuse_text_index_1_test() {
  nyowa.excuse_text(1) |> should.equal("17時回ったんで")
}
