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

pub fn got_timestamp_sets_idle_started_at_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.GotTimestamp(1_234_567.0))
  updated.idle_started_at |> should.equal(1_234_567.0)
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

pub fn button_hovered_does_not_increment_evade_count_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonHovered)
  // パターン発動時点では evade_count を増やさない
  updated.evade_count |> should.equal(0)
}

pub fn button_hovered_sets_first_interact_at_test() {
  let #(model, _) = nyowa.init(Nil)
  let #(updated, _) = nyowa.update(model, nyowa.ButtonHovered)
  // now() を使って記録されるため Some(_) になっていることだけ確認する
  case updated.first_interact_at {
    Some(_) -> Nil
    None -> should.fail()
  }
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
  // Dodge 再チェイスで evade_count が増える
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
  let fake2 = nyowa.CloneButton(pos: nyowa.Position(200.0, 0.0), is_real: False)
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
  // evade_count が +2 加算される
  updated.evade_count |> should.equal(3)
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
  // 自動進行中は evade_count を増やさない
  updated.evade_count |> should.equal(0)
}

pub fn excuse_expired_high_index_resets_to_idle_test() {
  let #(model, _) = nyowa.init(Nil)
  let excusing =
    nyowa.Model(
      ..model,
      phase: nyowa.Evading(nyowa.Excusing(index: 2, text: "システム障害（嘘）")),
      evade_count: 0,
    )
  let #(updated, _) = nyowa.update(excusing, nyowa.ExcuseExpired)
  updated.phase |> should.equal(nyowa.Idle)
  // ヒント吹き出しが表示される
  updated.dialogue
  |> should.equal(Some("…少し待ってくれると、気分が変わるかも……"))
  // Excuse 完走で evade_count +1
  updated.evade_count |> should.equal(1)
}

pub fn excuse_reset_updates_idle_started_at_test() {
  let #(model, _) = nyowa.init(Nil)
  let old_idle_started = 0.0
  let excusing =
    nyowa.Model(
      ..model,
      idle_started_at: old_idle_started,
      phase: nyowa.Evading(nyowa.Excusing(index: 2, text: "システム障害（嘘）")),
    )
  let #(updated, _) = nyowa.update(excusing, nyowa.ExcuseExpired)
  // idle_started_at が now() でリセットされているので 0.0 より大きい
  { updated.idle_started_at >. old_idle_started } |> should.equal(True)
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
// DetermineMood
// ---------------------------------------------------------------------------

pub fn mood_neutral_by_default_test() {
  nyowa.determine_mood(0, 5000.0) |> should.equal(nyowa.Neutral)
}

pub fn mood_grumpy_when_evade_count_3_test() {
  // evade_count >= 3, 放置短め → Grumpy
  nyowa.determine_mood(3, 5000.0) |> should.equal(nyowa.Grumpy)
}

pub fn mood_furious_when_evade_count_6_test() {
  // evade_count >= 6 → Furious
  nyowa.determine_mood(6, 5000.0) |> should.equal(nyowa.Furious)
}

pub fn mood_rested_when_idle_30s_test() {
  // idle >= 30s → Rested (evade_count に関係なく)
  nyowa.determine_mood(5, 35_000.0) |> should.equal(nyowa.Rested)
}

pub fn mood_rested_wins_over_furious_test() {
  // idle >= 30s なら evade_count >= 6 でも Rested が勝つ
  nyowa.determine_mood(8, 35_000.0) |> should.equal(nyowa.Rested)
}

pub fn mood_sleepy_when_idle_120s_test() {
  // idle >= 120s → Sleepy（完全な隠し機能、2分待ち）
  nyowa.determine_mood(0, 121_000.0) |> should.equal(nyowa.Sleepy)
}

pub fn mood_sleepy_wins_over_rested_and_furious_test() {
  // idle >= 120s なら Rested にも Furious にも勝つ
  nyowa.determine_mood(8, 125_000.0) |> should.equal(nyowa.Sleepy)
}

pub fn mood_not_sleepy_below_120s_test() {
  // idle < 120s なら Sleepy にならない（45s でも Rested 止まり）
  nyowa.determine_mood(0, 45_000.0) |> should.not_equal(nyowa.Sleepy)
}

// ---------------------------------------------------------------------------
// SelectFortune
// ---------------------------------------------------------------------------

pub fn select_fortune_returns_correct_mood_test() {
  let f = nyowa.select_fortune(nyowa.Furious, 0.1)
  f.mood |> should.equal(nyowa.Furious)
}


// ---------------------------------------------------------------------------
// do_catch の機嫌統合テスト (evade_count + idle_ms で Mood を決定)
// ---------------------------------------------------------------------------

pub fn catch_furious_mood_when_high_evade_count_test() {
  let #(model, _) = nyowa.init(Nil)
  // idle=5s (< 30s), evade_count=7 (>= 6) → Furious
  let m =
    nyowa.Model(
      ..model,
      evade_count: 7,
      idle_started_at: 0.0,
      first_interact_at: Some(5000.0),
      phase: nyowa.Evading(nyowa.Dodging(
        pos: nyowa.Position(0.0, 0.0),
        evade_count: 7,
      )),
      recently_touched: False,
    )
  let #(result, _) = nyowa.update(m, nyowa.ButtonClicked(0))
  case result.phase {
    nyowa.ShowResult(f) -> f.mood |> should.equal(nyowa.Furious)
    _ -> should.fail()
  }
}

pub fn catch_sleepy_mood_when_long_idle_test() {
  let #(model, _) = nyowa.init(Nil)
  // idle_started_at=0, first_interact_at=121s → idle=121s ≥ 120s → Sleepy
  let m =
    nyowa.Model(
      ..model,
      evade_count: 0,
      idle_started_at: 0.0,
      first_interact_at: Some(121_000.0),
      phase: nyowa.Evading(nyowa.Cooperating),
      recently_touched: False,
    )
  let #(result, _) = nyowa.update(m, nyowa.ButtonClicked(0))
  case result.phase {
    nyowa.ShowResult(f) -> f.mood |> should.equal(nyowa.Sleepy)
    _ -> should.fail()
  }
}

pub fn catch_rested_mood_when_idle_30s_test() {
  let #(model, _) = nyowa.init(Nil)
  // idle=35s ≥ 30s → Rested (evade_count に関係なく)
  let m =
    nyowa.Model(
      ..model,
      evade_count: 5,
      idle_started_at: 0.0,
      first_interact_at: Some(35_000.0),
      phase: nyowa.Evading(nyowa.Cooperating),
      recently_touched: False,
    )
  let #(result, _) = nyowa.update(m, nyowa.ButtonClicked(0))
  case result.phase {
    nyowa.ShowResult(f) -> f.mood |> should.equal(nyowa.Rested)
    _ -> should.fail()
  }
}

pub fn catch_dialogue_is_cleared_test() {
  let #(model, _) = nyowa.init(Nil)
  let m =
    nyowa.Model(
      ..model,
      evade_count: 0,
      idle_started_at: 0.0,
      dialogue: Some("えっ……にょわ……"),
      phase: nyowa.Evading(nyowa.Cooperating),
      recently_touched: False,
    )
  let #(result, _) = nyowa.update(m, nyowa.ButtonClicked(0))
  result.dialogue |> should.equal(None)
}

// ---------------------------------------------------------------------------
// PlayAgain: idle_started_at がリセットされることの確認
// ---------------------------------------------------------------------------

pub fn play_again_resets_idle_started_at_test() {
  let #(model, _) = nyowa.init(Nil)
  let old_m = nyowa.Model(..model, idle_started_at: 0.0)
  let #(reset, _) = nyowa.update(old_m, nyowa.PlayAgain)
  // now() で更新されるので 0.0 より大きいはず
  { reset.idle_started_at >. 0.0 } |> should.equal(True)
}

// ---------------------------------------------------------------------------
// ClearDialogue
// ---------------------------------------------------------------------------

pub fn clear_dialogue_clears_when_idle_test() {
  let #(model, _) = nyowa.init(Nil)
  let m = nyowa.Model(..model, phase: nyowa.Idle, dialogue: Some("テスト"))
  let #(updated, _) = nyowa.update(m, nyowa.ClearDialogue)
  updated.dialogue |> should.equal(None)
}

pub fn clear_dialogue_ignored_when_evading_test() {
  let #(model, _) = nyowa.init(Nil)
  let m =
    nyowa.Model(
      ..model,
      phase: nyowa.Evading(nyowa.Excusing(index: 0, text: "今休憩中")),
      dialogue: Some("今休憩中"),
    )
  let #(updated, _) = nyowa.update(m, nyowa.ClearDialogue)
  // Evading 中は古いタイマーを無視してダイアログを消さない
  updated.dialogue |> should.equal(Some("今休憩中"))
}
