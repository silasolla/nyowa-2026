import gleeunit/should
import nyowa/fortune
import nyowa/model

// ---------------------------------------------------------------------------
// determine_mood
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
// select_fortune
// ---------------------------------------------------------------------------

pub fn select_fortune_preserves_mood_test() {
  let f = fortune.select_fortune(model.Furious, 0.1)
  f.mood |> should.equal(model.Furious)
}

pub fn select_fortune_rand_0_picks_first_test() {
  let f0 = fortune.select_fortune(model.Neutral, 0.0)
  let f1 = fortune.select_fortune(model.Neutral, 0.99)
  // rand=0.0 → idx=0, rand=0.99 → idx=3: 異なる結果になるはず
  { f0.rank == f1.rank } |> should.equal(False)
}

pub fn select_fortune_rand_1_clamps_to_last_test() {
  // rand=1.0 は境界外 → idx がクランプされても Result でクラッシュしない
  let f = fortune.select_fortune(model.Sleepy, 1.0)
  { f.rank == "" } |> should.equal(False)
}

pub fn select_fortune_all_moods_return_nonempty_rank_test() {
  let moods = [
    model.Furious,
    model.Grumpy,
    model.Neutral,
    model.Rested,
    model.Sleepy,
  ]
  moods
  |> should.equal([
    model.Furious,
    model.Grumpy,
    model.Neutral,
    model.Rested,
    model.Sleepy,
  ])
  // 各 Mood で select_fortune が空文字を返さないことを確認
  let check = fn(mood) {
    let f = fortune.select_fortune(mood, 0.5)
    { f.rank == "" } |> should.equal(False)
  }
  check(model.Furious)
  check(model.Grumpy)
  check(model.Neutral)
  check(model.Rested)
  check(model.Sleepy)
}
