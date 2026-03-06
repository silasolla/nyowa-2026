import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import nyowa
import nyowa/content
import nyowa/fortune
import nyowa/model

pub fn main() -> Nil {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// init
// ---------------------------------------------------------------------------

pub fn init_phase_is_idle_test() {
  let #(m, _) = nyowa.init(Nil)
  m.phase |> should.equal(model.Idle)
}

pub fn init_evade_count_is_zero_test() {
  let #(m, _) = nyowa.init(Nil)
  m.evade_count |> should.equal(0)
}

pub fn init_recently_touched_is_false_test() {
  let #(m, _) = nyowa.init(Nil)
  m.recently_touched |> should.equal(False)
}

// ---------------------------------------------------------------------------
// ButtonHovered — パターン選択
// ---------------------------------------------------------------------------

pub fn button_hovered_from_idle_starts_evading_test() {
  let #(m, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(m, model.ButtonHovered)
  case updated.phase {
    model.Evading(_) -> Nil
    _ -> should.fail()
  }
}

pub fn button_hovered_does_not_increment_evade_count_test() {
  let #(m, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(m, model.ButtonHovered)
  updated.evade_count |> should.equal(0)
}

pub fn button_hovered_sets_first_interact_at_test() {
  let #(m, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(m, model.ButtonHovered)
  case updated.first_interact_at {
    Some(_) -> Nil
    None -> should.fail()
  }
}

pub fn button_hovered_sets_dialogue_test() {
  let #(m, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(m, model.ButtonHovered)
  case updated.dialogue {
    Some(_) -> Nil
    None -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Dodge パターン
// ---------------------------------------------------------------------------

pub fn dodge_hovered_again_increments_count_test() {
  let #(m, _) = nyowa.init(Nil)
  let dodging =
    model.Model(
      ..m,
      phase: model.Evading(model.Dodging(
        pos: model.Position(100.0, 100.0),
        evade_count: 2,
      )),
      evade_count: 2,
    )
  let #(updated, _) = nyowa.update(dodging, model.ButtonHovered)
  case updated.phase {
    model.Evading(model.Dodging(_, count)) -> count |> should.equal(3)
    _ -> should.fail()
  }
  updated.evade_count |> should.equal(3)
}

pub fn dodge_click_not_recently_touched_catches_test() {
  let #(m, _) = nyowa.init(Nil)
  let dodging =
    model.Model(
      ..m,
      phase: model.Evading(model.Dodging(
        pos: model.Position(100.0, 100.0),
        evade_count: 1,
      )),
      recently_touched: False,
    )
  let #(updated, _) = nyowa.update(dodging, model.ButtonClicked(0))
  case updated.phase {
    model.Drawing(_) -> Nil
    _ -> should.fail()
  }
}

pub fn dodge_click_recently_touched_is_ignored_test() {
  let #(m, _) = nyowa.init(Nil)
  let dodging =
    model.Model(
      ..m,
      phase: model.Evading(model.Dodging(
        pos: model.Position(100.0, 100.0),
        evade_count: 1,
      )),
      recently_touched: True,
    )
  let #(updated, _) = nyowa.update(dodging, model.ButtonClicked(0))
  updated.phase |> should.equal(dodging.phase)
}

// ---------------------------------------------------------------------------
// Clone パターン
// ---------------------------------------------------------------------------

pub fn clone_real_button_clicked_catches_test() {
  let #(m, _) = nyowa.init(Nil)
  let clones = [
    model.CloneButton(pos: model.Position(0.0, 0.0), is_real: False),
    model.CloneButton(pos: model.Position(100.0, 0.0), is_real: True),
    model.CloneButton(pos: model.Position(200.0, 0.0), is_real: False),
  ]
  let cloning = model.Model(..m, phase: model.Evading(model.Cloning(clones:)))
  let #(updated, _) = nyowa.update(cloning, model.ButtonClicked(1))
  case updated.phase {
    model.Drawing(_) -> Nil
    _ -> should.fail()
  }
}

pub fn clone_fake_button_clicked_removes_it_test() {
  let #(m, _) = nyowa.init(Nil)
  let fake0 = model.CloneButton(pos: model.Position(0.0, 0.0), is_real: False)
  let real1 = model.CloneButton(pos: model.Position(100.0, 0.0), is_real: True)
  let fake2 = model.CloneButton(pos: model.Position(200.0, 0.0), is_real: False)
  let cloning =
    model.Model(
      ..m,
      phase: model.Evading(model.Cloning(clones: [fake0, real1, fake2])),
      evade_count: 1,
    )
  let #(updated, _) = nyowa.update(cloning, model.ButtonClicked(0))
  updated.phase
  |> should.equal(model.Evading(model.Cloning(clones: [real1, fake2])))
  updated.evade_count |> should.equal(3)
  updated.dialogue |> should.equal(Some(content.clone_fake_hit))
}

// ---------------------------------------------------------------------------
// Excuse パターン
// ---------------------------------------------------------------------------

pub fn excuse_expired_low_index_advances_to_next_test() {
  let #(m, _) = nyowa.init(Nil)
  let excusing =
    model.Model(
      ..m,
      phase: model.Evading(model.Excusing(
        index: 0,
        text: content.excuse_text(0),
      )),
    )
  let #(updated, _) = nyowa.update(excusing, model.ExcuseExpired)
  case updated.phase {
    model.Evading(model.Excusing(index: 1, text: _)) -> Nil
    _ -> should.fail()
  }
  updated.evade_count |> should.equal(0)
}

pub fn excuse_expired_high_index_resets_to_idle_test() {
  let #(m, _) = nyowa.init(Nil)
  let excusing =
    model.Model(
      ..m,
      phase: model.Evading(model.Excusing(
        index: 2,
        text: content.excuse_text(2),
      )),
      evade_count: 0,
    )
  let #(updated, _) = nyowa.update(excusing, model.ExcuseExpired)
  updated.phase |> should.equal(model.Idle)
  updated.dialogue |> should.equal(Some(content.excuse_hint))
  updated.evade_count |> should.equal(1)
}

pub fn excuse_reset_updates_idle_started_at_test() {
  let #(m, _) = nyowa.init(Nil)
  let old_idle_started = 0.0
  let excusing =
    model.Model(
      ..m,
      idle_started_at: old_idle_started,
      phase: model.Evading(model.Excusing(
        index: 2,
        text: content.excuse_text(2),
      )),
    )
  let #(updated, _) = nyowa.update(excusing, model.ExcuseExpired)
  { updated.idle_started_at >. old_idle_started } |> should.equal(True)
}

pub fn excuse_button_click_is_ignored_test() {
  let #(m, _) = nyowa.init(Nil)
  let excusing =
    model.Model(
      ..m,
      phase: model.Evading(model.Excusing(
        index: 0,
        text: content.excuse_text(0),
      )),
    )
  let #(updated, _) = nyowa.update(excusing, model.ButtonClicked(0))
  updated.phase |> should.equal(excusing.phase)
}

// ---------------------------------------------------------------------------
// Camo パターン
// ---------------------------------------------------------------------------

pub fn camo_button_click_catches_test() {
  let #(m, _) = nyowa.init(Nil)
  let camo =
    model.Model(
      ..m,
      phase: model.Evading(
        model.Camouflaging(pos: model.Position(100.0, 200.0)),
      ),
    )
  let #(updated, _) = nyowa.update(camo, model.ButtonClicked(0))
  case updated.phase {
    model.Drawing(_) -> Nil
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Cooperate パターン
// ---------------------------------------------------------------------------

pub fn cooperate_button_click_catches_test() {
  let #(m, _) = nyowa.init(Nil)
  let coop = model.Model(..m, phase: model.Evading(model.Cooperating))
  let #(updated, _) = nyowa.update(coop, model.ButtonClicked(0))
  case updated.phase {
    model.Drawing(_) -> Nil
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// GhostClickExpired
// ---------------------------------------------------------------------------

pub fn ghost_click_expired_clears_flag_test() {
  let #(m, _) = nyowa.init(Nil)
  let #(touched, _) = nyowa.update(m, model.ButtonTouched)
  touched.recently_touched |> should.equal(True)
  let #(cleared, _) = nyowa.update(touched, model.GhostClickExpired)
  cleared.recently_touched |> should.equal(False)
}

// ---------------------------------------------------------------------------
// PlayAgain
// ---------------------------------------------------------------------------

pub fn play_again_full_reset_test() {
  let #(m, _) = nyowa.init(Nil)
  let #(m1, _) = nyowa.update(m, model.ButtonHovered)
  let #(m2, _) = nyowa.update(m1, model.ButtonClicked(0))
  let #(reset, _) = nyowa.update(m2, model.PlayAgain)
  reset.phase |> should.equal(model.Idle)
  reset.evade_count |> should.equal(0)
  reset.recently_touched |> should.equal(False)
  reset.first_interact_at |> should.equal(None)
  reset.dialogue |> should.equal(None)
}

// ---------------------------------------------------------------------------
// DetermineMood
// ---------------------------------------------------------------------------

pub fn mood_neutral_by_default_test() {
  fortune.determine_mood(0, 5000.0) |> should.equal(model.Neutral)
}

pub fn mood_grumpy_when_evade_count_3_test() {
  fortune.determine_mood(3, 5000.0) |> should.equal(model.Grumpy)
}

pub fn mood_furious_when_evade_count_6_test() {
  fortune.determine_mood(6, 5000.0) |> should.equal(model.Furious)
}

pub fn mood_rested_when_idle_30s_test() {
  fortune.determine_mood(5, 35_000.0) |> should.equal(model.Rested)
}

pub fn mood_rested_wins_over_furious_test() {
  fortune.determine_mood(8, 35_000.0) |> should.equal(model.Rested)
}

pub fn mood_sleepy_when_idle_120s_test() {
  fortune.determine_mood(0, 121_000.0) |> should.equal(model.Sleepy)
}

pub fn mood_sleepy_wins_over_rested_and_furious_test() {
  fortune.determine_mood(8, 125_000.0) |> should.equal(model.Sleepy)
}

pub fn mood_not_sleepy_below_120s_test() {
  fortune.determine_mood(0, 45_000.0) |> should.not_equal(model.Sleepy)
}

// ---------------------------------------------------------------------------
// SelectFortune
// ---------------------------------------------------------------------------

pub fn select_fortune_returns_correct_mood_test() {
  let f = fortune.select_fortune(model.Furious, 0.1)
  f.mood |> should.equal(model.Furious)
}

// ---------------------------------------------------------------------------
// do_catch の統合テスト (Drawing フェーズへの移行を確認)
// ---------------------------------------------------------------------------

pub fn catch_goes_to_drawing_phase_test() {
  let #(m, _) = nyowa.init(Nil)
  let c =
    model.Model(
      ..m,
      phase: model.Evading(model.Cooperating),
      recently_touched: False,
    )
  let #(result, _) = nyowa.update(c, model.ButtonClicked(0))
  case result.phase {
    model.Drawing(_) -> Nil
    _ -> should.fail()
  }
}

pub fn catch_furious_mood_when_high_evade_count_test() {
  let #(m, _) = nyowa.init(Nil)
  let c =
    model.Model(
      ..m,
      evade_count: 7,
      idle_started_at: 0.0,
      first_interact_at: Some(5000.0),
      phase: model.Evading(model.Dodging(
        pos: model.Position(0.0, 0.0),
        evade_count: 7,
      )),
      recently_touched: False,
    )
  let #(drawing, _) = nyowa.update(c, model.ButtonClicked(0))
  case drawing.phase {
    model.Drawing(_) -> Nil
    _ -> should.fail()
  }
}

pub fn catch_sleepy_mood_when_long_idle_test() {
  let #(m, _) = nyowa.init(Nil)
  let c =
    model.Model(
      ..m,
      evade_count: 0,
      idle_started_at: 0.0,
      first_interact_at: Some(121_000.0),
      phase: model.Evading(model.Cooperating),
      recently_touched: False,
    )
  let #(drawing, _) = nyowa.update(c, model.ButtonClicked(0))
  case drawing.phase {
    model.Drawing(_) -> Nil
    _ -> should.fail()
  }
}

pub fn catch_rested_mood_when_idle_30s_test() {
  let #(m, _) = nyowa.init(Nil)
  let c =
    model.Model(
      ..m,
      evade_count: 5,
      idle_started_at: 0.0,
      first_interact_at: Some(35_000.0),
      phase: model.Evading(model.Cooperating),
      recently_touched: False,
    )
  let #(drawing, _) = nyowa.update(c, model.ButtonClicked(0))
  case drawing.phase {
    model.Drawing(_) -> Nil
    _ -> should.fail()
  }
}

pub fn catch_dialogue_is_set_for_drawing_test() {
  let #(m, _) = nyowa.init(Nil)
  let c =
    model.Model(
      ..m,
      evade_count: 0,
      idle_started_at: 0.0,
      dialogue: Some(content.dodge_initial),
      phase: model.Evading(model.Cooperating),
      recently_touched: False,
    )
  let #(result, _) = nyowa.update(c, model.ButtonClicked(0))
  case result.dialogue {
    Some(_) -> Nil
    None -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// DrawInterruption / DrawComplete
// ---------------------------------------------------------------------------

pub fn draw_interruption_paused_updates_dialogue_test() {
  let #(m, _) = nyowa.init(Nil)
  let drawing =
    model.Model(
      ..m,
      phase: model.Drawing(model.Spinning),
      dialogue: Some(content.draw_spinning),
    )
  let #(updated, _) =
    nyowa.update(drawing, model.DrawInterruption(model.Paused))
  updated.phase |> should.equal(model.Drawing(model.Paused))
  updated.dialogue |> should.equal(Some(content.draw_paused))
}

pub fn draw_interruption_reversing_updates_dialogue_test() {
  let #(m, _) = nyowa.init(Nil)
  let drawing =
    model.Model(
      ..m,
      phase: model.Drawing(model.Spinning),
      dialogue: Some(content.draw_spinning),
    )
  let #(updated, _) =
    nyowa.update(drawing, model.DrawInterruption(model.Reversing))
  updated.phase |> should.equal(model.Drawing(model.Reversing))
  updated.dialogue |> should.equal(Some(content.draw_reversing))
}

pub fn draw_complete_transitions_to_show_result_test() {
  let #(m, _) = nyowa.init(Nil)
  let drawing = model.Model(..m, phase: model.Drawing(model.Spinning))
  let ft = model.Fortune(rank: "大吉", message: "テスト", mood: model.Neutral)
  let #(updated, _) = nyowa.update(drawing, model.DrawComplete(ft))
  updated.phase |> should.equal(model.ShowResult(ft))
}

pub fn draw_complete_clears_dialogue_test() {
  let #(m, _) = nyowa.init(Nil)
  let drawing =
    model.Model(
      ..m,
      phase: model.Drawing(model.Spinning),
      dialogue: Some("にょわにょわ……"),
    )
  let ft = model.Fortune(rank: "大吉", message: "テスト", mood: model.Neutral)
  let #(updated, _) = nyowa.update(drawing, model.DrawComplete(ft))
  updated.dialogue |> should.equal(None)
}

pub fn draw_complete_ignored_when_not_drawing_test() {
  let #(m, _) = nyowa.init(Nil)
  let idle = model.Model(..m, phase: model.Idle)
  let ft = model.Fortune(rank: "大吉", message: "テスト", mood: model.Neutral)
  let #(updated, _) = nyowa.update(idle, model.DrawComplete(ft))
  updated.phase |> should.equal(model.Idle)
}

pub fn draw_interruption_ignored_when_not_drawing_test() {
  let #(m, _) = nyowa.init(Nil)
  let idle = model.Model(..m, phase: model.Idle)
  let #(updated, _) = nyowa.update(idle, model.DrawInterruption(model.Paused))
  updated.phase |> should.equal(model.Idle)
}

// ---------------------------------------------------------------------------
// PlayAgain: idle_started_at がリセットされることの確認
// ---------------------------------------------------------------------------

pub fn play_again_resets_idle_started_at_test() {
  let #(m, _) = nyowa.init(Nil)
  let old_m = model.Model(..m, idle_started_at: 0.0)
  let #(reset, _) = nyowa.update(old_m, model.PlayAgain)
  { reset.idle_started_at >. 0.0 } |> should.equal(True)
}

// ---------------------------------------------------------------------------
// ClearDialogue
// ---------------------------------------------------------------------------

pub fn clear_dialogue_clears_when_idle_test() {
  let #(m, _) = nyowa.init(Nil)
  let c = model.Model(..m, phase: model.Idle, dialogue: Some("テスト"))
  let #(updated, _) = nyowa.update(c, model.ClearDialogue)
  updated.dialogue |> should.equal(None)
}

pub fn clear_dialogue_ignored_when_evading_test() {
  let #(m, _) = nyowa.init(Nil)
  let excuse_0 = content.excuse_text(0)
  let c =
    model.Model(
      ..m,
      phase: model.Evading(model.Excusing(index: 0, text: excuse_0)),
      dialogue: Some(excuse_0),
    )
  let #(updated, _) = nyowa.update(c, model.ClearDialogue)
  updated.dialogue |> should.equal(Some(excuse_0))
}
