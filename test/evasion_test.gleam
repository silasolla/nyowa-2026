import gleeunit/should
import nyowa/content
import nyowa/evasion
import nyowa/model

// ---------------------------------------------------------------------------
// select_evasion_pattern — パターン選択境界値
// ---------------------------------------------------------------------------

// テスト用の固定値
const vp = #(1000.0, 800.0)

const fixed_pos = model.Position(100.0, 200.0)

fn fixed_clones() -> List(model.CloneButton) {
  [
    model.CloneButton(pos: model.Position(0.0, 0.0), is_real: False),
    model.CloneButton(pos: model.Position(100.0, 0.0), is_real: True),
    model.CloneButton(pos: model.Position(200.0, 0.0), is_real: False),
  ]
}

pub fn pattern_dodge_when_rand_lt_03_test() {
  let #(state, _, _) =
    evasion.select_evasion_pattern(0.1, fixed_pos, fixed_clones())
  case state {
    model.Dodging(pos, _) -> pos |> should.equal(fixed_pos)
    _ -> should.fail()
  }
}

pub fn pattern_clone_when_rand_03_to_05_test() {
  let #(state, _, _) =
    evasion.select_evasion_pattern(0.4, fixed_pos, fixed_clones())
  case state {
    model.Cloning(clones) -> clones |> should.equal(fixed_clones())
    _ -> should.fail()
  }
}

pub fn pattern_excuse_when_rand_05_to_07_test() {
  let #(state, _, _) =
    evasion.select_evasion_pattern(0.6, fixed_pos, fixed_clones())
  case state {
    model.Excusing(index: 0, text: _) -> Nil
    _ -> should.fail()
  }
}

pub fn pattern_camo_when_rand_07_to_085_test() {
  let #(state, _, _) =
    evasion.select_evasion_pattern(0.8, fixed_pos, fixed_clones())
  case state {
    model.Camouflaging(pos) -> pos |> should.equal(fixed_pos)
    _ -> should.fail()
  }
}

pub fn pattern_cooperate_when_rand_gte_085_test() {
  let #(state, _, _) =
    evasion.select_evasion_pattern(0.9, fixed_pos, fixed_clones())
  state |> should.equal(model.Cooperating)
}

pub fn pattern_dodge_sets_initial_dialogue_test() {
  let #(_, dialogue, _) =
    evasion.select_evasion_pattern(0.1, fixed_pos, fixed_clones())
  dialogue |> should.equal(content.dodge_initial)
}

pub fn pattern_clone_sets_initial_dialogue_test() {
  let #(_, dialogue, _) =
    evasion.select_evasion_pattern(0.4, fixed_pos, fixed_clones())
  dialogue |> should.equal(content.clone_initial)
}

// ---------------------------------------------------------------------------
// generate_clones — real_idx の決定
// ---------------------------------------------------------------------------

pub fn generate_clones_first_is_real_when_rand_near_0_test() {
  // float.round(0.1 * 2.0) = float.round(0.2) = 0 → idx 0 が real
  let p0 = model.Position(0.0, 0.0)
  let p1 = model.Position(100.0, 0.0)
  let p2 = model.Position(200.0, 0.0)
  let clones = evasion.generate_clones(0.1, p0, p1, p2)
  case clones {
    [
      model.CloneButton(_, True),
      model.CloneButton(_, False),
      model.CloneButton(_, False),
    ] -> Nil
    _ -> should.fail()
  }
}

pub fn generate_clones_second_is_real_when_rand_near_05_test() {
  // float.round(0.5 * 2.0) = float.round(1.0) = 1 → idx 1 が real
  let p0 = model.Position(0.0, 0.0)
  let p1 = model.Position(100.0, 0.0)
  let p2 = model.Position(200.0, 0.0)
  let clones = evasion.generate_clones(0.5, p0, p1, p2)
  case clones {
    [
      model.CloneButton(_, False),
      model.CloneButton(_, True),
      model.CloneButton(_, False),
    ] -> Nil
    _ -> should.fail()
  }
}

pub fn generate_clones_third_is_real_when_rand_near_1_test() {
  // float.round(0.8 * 2.0) = float.round(1.6) = 2 → idx 2 が real
  let p0 = model.Position(0.0, 0.0)
  let p1 = model.Position(100.0, 0.0)
  let p2 = model.Position(200.0, 0.0)
  let clones = evasion.generate_clones(0.8, p0, p1, p2)
  case clones {
    [
      model.CloneButton(_, False),
      model.CloneButton(_, False),
      model.CloneButton(_, True),
    ] -> Nil
    _ -> should.fail()
  }
}

pub fn generate_clones_positions_are_preserved_test() {
  let p0 = model.Position(10.0, 20.0)
  let p1 = model.Position(30.0, 40.0)
  let p2 = model.Position(50.0, 60.0)
  let clones = evasion.generate_clones(0.1, p0, p1, p2)
  case clones {
    [
      model.CloneButton(pos0, _),
      model.CloneButton(pos1, _),
      model.CloneButton(pos2, _),
    ] -> {
      pos0 |> should.equal(p0)
      pos1 |> should.equal(p1)
      pos2 |> should.equal(p2)
    }
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// random_pos — 座標計算
// ---------------------------------------------------------------------------

pub fn random_pos_zero_gives_margin_only_test() {
  // rx=0.0, ry=0.0 → x=margin, y=margin
  let pos = evasion.random_pos(vp, 0.0, 0.0)
  pos |> should.equal(model.Position(24.0, 24.0))
}

pub fn random_pos_one_gives_max_extent_test() {
  // usable_w = 1000 - 220 - 48 = 732, usable_h = 800 - 64 - 48 = 688
  // rx=1.0 → x = 732 + 24 = 756, ry=1.0 → y = 688 + 24 = 712
  let pos = evasion.random_pos(vp, 1.0, 1.0)
  pos |> should.equal(model.Position(756.0, 712.0))
}

pub fn random_pos_clamps_usable_area_to_zero_test() {
  // 非常に小さいビューポートでは usable が 0 になり margin だけになる
  let tiny_vp = #(100.0, 50.0)
  let pos = evasion.random_pos(tiny_vp, 0.5, 0.5)
  // usable_w = max(100-220-48, 0) = 0, usable_h = max(50-64-48, 0) = 0
  pos |> should.equal(model.Position(24.0, 24.0))
}

// ---------------------------------------------------------------------------
// clone_at / remove_at_index — リストユーティリティ
// ---------------------------------------------------------------------------

pub fn clone_at_returns_correct_element_test() {
  let a = model.CloneButton(pos: model.Position(0.0, 0.0), is_real: False)
  let b = model.CloneButton(pos: model.Position(1.0, 0.0), is_real: True)
  let c = model.CloneButton(pos: model.Position(2.0, 0.0), is_real: False)
  evasion.clone_at([a, b, c], 1) |> should.equal(Ok(b))
}

pub fn clone_at_returns_error_when_out_of_bounds_test() {
  let a = model.CloneButton(pos: model.Position(0.0, 0.0), is_real: False)
  evasion.clone_at([a], 5) |> should.equal(Error(Nil))
}

pub fn clone_at_returns_error_on_empty_list_test() {
  evasion.clone_at([], 0) |> should.equal(Error(Nil))
}

pub fn remove_at_index_removes_first_test() {
  let a = model.CloneButton(pos: model.Position(0.0, 0.0), is_real: False)
  let b = model.CloneButton(pos: model.Position(1.0, 0.0), is_real: True)
  let c = model.CloneButton(pos: model.Position(2.0, 0.0), is_real: False)
  evasion.remove_at_index([a, b, c], 0) |> should.equal([b, c])
}

pub fn remove_at_index_removes_middle_test() {
  let a = model.CloneButton(pos: model.Position(0.0, 0.0), is_real: False)
  let b = model.CloneButton(pos: model.Position(1.0, 0.0), is_real: True)
  let c = model.CloneButton(pos: model.Position(2.0, 0.0), is_real: False)
  evasion.remove_at_index([a, b, c], 1) |> should.equal([a, c])
}
