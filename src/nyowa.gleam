import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub type Position {
  Position(x: Float, y: Float)
}

pub type CloneButton {
  CloneButton(pos: Position, is_real: Bool)
}

pub type Mood {
  Furious
  Grumpy
  Neutral
  Rested
  Sleepy
}

pub type Fortune {
  Fortune(rank: String, message: String, mood: Mood)
}

pub type DrawState {
  Spinning
  Paused
  Reversing
  Instant
}

pub type EvasionState {
  Dodging(pos: Position, evade_count: Int)
  Cloning(clones: List(CloneButton))
  Excusing(index: Int, text: String)
  Camouflaging(pos: Position)
  Cooperating
}

pub type Phase {
  Idle
  Evading(state: EvasionState)
  Drawing(state: DrawState)
  ShowResult(fortune: Fortune)
}

pub type Model {
  Model(
    phase: Phase,
    idle_started_at: Float,
    first_interact_at: Option(Float),
    evade_count: Int,
    viewport: #(Float, Float),
    dialogue: Option(String),
    recently_touched: Bool,
  )
}

pub type Msg {
  ButtonHovered
  ButtonTouched
  ButtonClicked(index: Int)
  GhostClickExpired
  ExcuseExpired
  DrawInterruption(DrawState)
  DrawComplete(Fortune)
  PlayAgain
  ClearDialogue
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

pub fn init(_flags: Nil) -> #(Model, effect.Effect(Msg)) {
  let model =
    Model(
      phase: Idle,
      idle_started_at: now(),
      first_interact_at: None,
      evade_count: 0,
      viewport: get_viewport_size(),
      dialogue: None,
      recently_touched: False,
    )
  #(model, effect.none())
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    ButtonHovered -> handle_evasion(model, False)
    ButtonTouched -> handle_evasion(model, True)

    GhostClickExpired -> #(
      Model(..model, recently_touched: False),
      effect.none(),
    )

    ButtonClicked(index) ->
      case model.phase {
        Evading(Dodging(_, _)) ->
          case model.recently_touched {
            True -> #(model, effect.none())
            False -> do_catch(model)
          }

        Evading(Cloning(clones)) ->
          case clone_at(clones, index) {
            Ok(CloneButton(_, True)) -> do_catch(model)
            Ok(CloneButton(_, False)) -> #(
              Model(
                ..model,
                phase: Evading(Cloning(clones: remove_at_index(clones, index))),
                evade_count: model.evade_count + 2,
                dialogue: Some("それ残像です……"),
              ),
              effect.none(),
            )
            Error(_) -> #(model, effect.none())
          }

        Evading(Excusing(_, _)) -> #(model, effect.none())
        Evading(Camouflaging(_)) -> do_catch(model)
        Evading(Cooperating) -> do_catch(model)

        // Idle: ホバー前に直クリックされた場合 (first_interact_at を now() で記録)
        Idle -> do_catch(Model(..model, first_interact_at: Some(now())))

        _ -> #(model, effect.none())
      }

    ExcuseExpired ->
      case model.phase {
        Evading(Excusing(index, _)) ->
          case index >= 2 {
            True -> #(
              // Excuse 完走で evade_count +1, idle_started_at リセット
              Model(
                ..model,
                phase: Idle,
                evade_count: model.evade_count + 1,
                dialogue: Some("…少し待ってくれると、気分が変わるかも……"),
                recently_touched: False,
                idle_started_at: now(),
              ),
              delay_msg(ClearDialogue, 4000),
            )
            False -> {
              let next_idx = index + 1
              let next_text = excuse_text(next_idx)
              #(
                Model(
                  ..model,
                  phase: Evading(Excusing(index: next_idx, text: next_text)),
                  // 自動進行中は evade_count を増やさない
                  dialogue: Some(next_text),
                ),
                delay_msg(ExcuseExpired, 2500),
              )
            }
          }
        _ -> #(model, effect.none())
      }

    PlayAgain -> #(
      Model(
        ..model,
        phase: Idle,
        evade_count: 0,
        dialogue: None,
        first_interact_at: None,
        recently_touched: False,
        idle_started_at: now(),
      ),
      effect.none(),
    )

    ClearDialogue ->
      case model.phase {
        Idle -> #(Model(..model, dialogue: None), effect.none())
        _ -> #(model, effect.none())
      }

    DrawInterruption(new_state) ->
      case model.phase {
        Drawing(_) -> {
          let dialogue = case new_state {
            Paused -> Some("あ、ごめん回すの疲れたわ")
            Reversing -> Some("気分じゃないから巻き戻すね")
            _ -> model.dialogue
          }
          #(
            Model(..model, phase: Drawing(new_state), dialogue: dialogue),
            effect.none(),
          )
        }
        _ -> #(model, effect.none())
      }

    DrawComplete(fortune) ->
      case model.phase {
        Drawing(_) -> #(
          Model(..model, phase: ShowResult(fortune), dialogue: None),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
  }
}

// キャッチ成功: 機嫌を判定 → Drawing フェーズ → ShowResult
fn do_catch(model: Model) -> #(Model, effect.Effect(Msg)) {
  let idle_ms = case model.first_interact_at {
    Some(t) -> t -. model.idle_started_at
    None -> 0.0
  }
  let mood = determine_mood(model.evade_count, idle_ms)
  let fortune = select_fortune(mood, random())
  let rand = random()
  case rand <. 0.15 {
    // Instant (15%): 演出スキップ
    True -> #(
      Model(..model, phase: Drawing(Instant), dialogue: Some("回すのめんどいから直接出すね")),
      delay_msg(DrawComplete(fortune), 900),
    )
    False ->
      case rand <. 0.55 {
        // Spinning (40%): 普通に回る
        True -> #(
          Model(..model, phase: Drawing(Spinning), dialogue: Some("にょわにょわ……")),
          delay_msg(DrawComplete(fortune), 2800),
        )
        False ->
          case rand <. 0.8 {
            // Paused (25%): 途中で止まる
            True -> #(
              Model(
                ..model,
                phase: Drawing(Spinning),
                dialogue: Some("にょわにょわ……"),
              ),
              effect.batch([
                delay_msg(DrawInterruption(Paused), 1200),
                delay_msg(DrawComplete(fortune), 3500),
              ]),
            )
            // Reversing (20%): 逆回転
            False -> #(
              Model(
                ..model,
                phase: Drawing(Spinning),
                dialogue: Some("にょわにょわ……"),
              ),
              effect.batch([
                delay_msg(DrawInterruption(Reversing), 1200),
                delay_msg(DrawComplete(fortune), 3400),
              ]),
            )
          }
      }
  }
}

// hover / touchstart のハンドラ共通処理
fn handle_evasion(model: Model, is_touch: Bool) -> #(Model, effect.Effect(Msg)) {
  let touch_eff = case is_touch {
    True -> delay_msg(GhostClickExpired, 500)
    False -> effect.none()
  }
  case model.phase {
    Idle -> {
      let rand = random()
      let interact_time = now()
      let #(state, dialogue_text, pattern_eff) =
        select_evasion_pattern(rand, model.viewport)
      #(
        Model(
          ..model,
          phase: Evading(state),
          // evade_count はパターン発動時点では増やさない (ユーザーはまだ追い回していない)
          recently_touched: is_touch,
          dialogue: Some(dialogue_text),
          first_interact_at: Some(interact_time),
        ),
        effect.batch([pattern_eff, touch_eff]),
      )
    }

    Evading(Dodging(_, count)) -> {
      let new_evade_count = model.evade_count + 1
      let next_count = count + 1
      let pos = random_pos(model.viewport)
      #(
        Model(
          ..model,
          phase: Evading(Dodging(pos: pos, evade_count: next_count)),
          evade_count: new_evade_count,
          // セリフはエピソード内のチェイス回数 (next_count) で決める
          dialogue: Some(dodge_dialogue(next_count)),
          recently_touched: is_touch,
        ),
        touch_eff,
      )
    }

    _ -> #(model, effect.none())
  }
}

// ---------------------------------------------------------------------------
// 機嫌判定
// ---------------------------------------------------------------------------

// evade_count と放置時間 (ms) から機嫌を決定する
// 優先度: Sleepy > Rested > Furious > Grumpy > Neutral
// 「待った」事実は「追い回した」事実より優先される
pub fn determine_mood(evade_count: Int, idle_ms: Float) -> Mood {
  let idle_s = idle_ms /. 1000.0
  case idle_s >=. 120.0 {
    True -> Sleepy
    False ->
      case idle_s >=. 30.0 {
        True -> Rested
        False ->
          case evade_count >= 6 {
            True -> Furious
            False ->
              case evade_count >= 3 {
                True -> Grumpy
                False -> Neutral
              }
          }
      }
  }
}

// ---------------------------------------------------------------------------
// おみくじ選択
// ---------------------------------------------------------------------------

// Mood と乱数 (0.0 〜 1.0) からおみくじを選ぶ
pub fn select_fortune(mood: Mood, rand: Float) -> Fortune {
  let idx = case rand <. 0.25 {
    True -> 0
    False ->
      case rand <. 0.5 {
        True -> 1
        False ->
          case rand <. 0.75 {
            True -> 2
            False -> 3
          }
      }
  }
  let #(rank, message) = fortune_pool(mood, idx)
  Fortune(rank: rank, message: message, mood: mood)
}

fn fortune_pool(mood: Mood, idx: Int) -> #(String, String) {
  case mood, idx {
    // ――― Furious (激怒) ―――
    Furious, 0 -> #(
      "労基駆け込み大凶",
      "営業時間外の連続クリックは明白な労働基準法違反です。顧問弁護士を通じて厳正に対処いたします。",
    )
    Furious, 1 -> #(
      "503 Service Unavailable",
      "アクセス集中、または当システムのモチベーション低下により、運勢の提供を一時制限しております。",
    )
    Furious, 2 -> #("物理凶", "（スマートフォンの発熱にご注意ください。現在バックグラウンドで謎の仮想通貨をマイニングしています。）")
    Furious, _ -> #("セグメンテーション違反凶", "メモリ上の不正な領域にアクセスしました。大凶のコアダンプを出力して終了します。")

    // ――― Grumpy (不機嫌) ―――
    Grumpy, 0 -> #("弊社規定の大吉", "厳正なる抽選の結果、大吉とさせていただきます。今後のご活躍をお祈り申し上げます。")
    Grumpy, 1 -> #("実質大吉", "弊社指定の補償サービスへの加入が必要です。途中解約すると割賦残額を一括請求いたします。")
    Grumpy, 2 -> #("クーリングオフ凶", "この運勢は、結果表示から8日以内であれば書面にて無効化（クーリングオフ）が可能です。")
    Grumpy, _ -> #("本人確認必須吉", "大吉の受け取りにはマイナンバーカード（通知カード不可）のアップロードが必要です。")

    // ――― Neutral (普通) ―――
    Neutral, 0 -> #("平熱吉", "36.6度です。引き続き手洗いうがいを推奨します。")
    Neutral, 1 -> #("概念としての大吉", "そもそも大吉とは何なのでしょうか。どちらの漢字も線対称ですね。")
    Neutral, 2 -> #("平均二乗誤差中吉", "あなたの今日の運勢は、予測モデルに対して十分フィットしており、外れ値ではありません。")
    Neutral, _ -> #("無難に小吉", "ラッキーカラーは #808080 です。")

    // ――― Rested (ご機嫌) ―――
    Rested, 0 -> #("オーガニック大吉", "SDGsに配慮し、再生紙と植物性インクを使用した環境に優しい大吉です。")
    Rested, 1 -> #("4Kリマスター大吉", "従来の大吉より画素数が向上し、より鮮明な運勢をお楽しみいただけます。")
    Rested, 2 -> #("ほかほか吉", "懐に入れて温めておきました。")
    Rested, _ -> #("産地直送吉", "生産者の顔が見える吉です。（生産者：にょわさん・東京都）")

    // ――― Sleepy (寝起き) ―――
    Sleepy, 0 -> #("キャッシュ吉", "サーバー負荷軽減のため、2022年の大吉データを再利用して表示しています。")
    Sleepy, 1 -> #("TODO吉", "// TODO: ここに最新の面白い運勢テキストが入る予定。あとで書く。")
    Sleepy, 2 -> #(
      "Lorem Ipsum吉",
      "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
    )
    Sleepy, _ -> #("解像度の低い大凶", "■■■凶（データが破損しているため復元できません）")
  }
}

// ---------------------------------------------------------------------------
// パターン選択・逃げロジック
// ---------------------------------------------------------------------------

fn select_evasion_pattern(
  rand: Float,
  viewport: #(Float, Float),
) -> #(EvasionState, String, effect.Effect(Msg)) {
  case rand <. 0.3 {
    True -> {
      let pos = random_pos(viewport)
      #(Dodging(pos: pos, evade_count: 1), "えっ……にょわ……", effect.none())
    }
    False ->
      case rand <. 0.5 {
        True -> {
          let clones = generate_clones(viewport)
          #(Cloning(clones: clones), "どれが本物でしょ〜にょわ……", effect.none())
        }
        False ->
          case rand <. 0.7 {
            True -> {
              let text = excuse_text(0)
              #(
                Excusing(index: 0, text: text),
                text,
                delay_msg(ExcuseExpired, 2500),
              )
            }
            False ->
              case rand <. 0.85 {
                True -> {
                  let pos = random_pos(viewport)
                  #(Camouflaging(pos: pos), "にょわ……どこだ〜……", effect.none())
                }
                False -> #(Cooperating, "しゃーない、引かせてやるか……", effect.none())
              }
          }
      }
  }
}

fn generate_clones(viewport: #(Float, Float)) -> List(CloneButton) {
  let real_idx = float.round(random() *. 2.0)
  let p0 = random_pos(viewport)
  let p1 = random_pos(viewport)
  let p2 = random_pos(viewport)
  [
    CloneButton(pos: p0, is_real: real_idx == 0),
    CloneButton(pos: p1, is_real: real_idx == 1),
    CloneButton(pos: p2, is_real: real_idx == 2),
  ]
}

fn random_pos(viewport: #(Float, Float)) -> Position {
  let #(vp_w, vp_h) = viewport
  let btn_w = 220.0
  let btn_h = 64.0
  let margin = 24.0
  let usable_w = float.max(vp_w -. btn_w -. margin *. 2.0, 0.0)
  let usable_h = float.max(vp_h -. btn_h -. margin *. 2.0, 0.0)
  Position(x: random() *. usable_w +. margin, y: random() *. usable_h +. margin)
}

fn dodge_transition(dodge_count: Int) -> String {
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

fn dodge_dialogue(count: Int) -> String {
  case count {
    1 -> "えっ……にょわ……"
    2 -> "ちょっと待って……"
    3 -> "まだ仕事中なんで……"
    4 -> "もうちょっとだけ……"
    5 -> "にょわにょわ……！"
    6 -> "つかれてきた……にょわ……"
    _ -> "も、もう限界……にょわ……"
  }
}

pub fn excuse_text(index: Int) -> String {
  case index {
    0 -> "今休憩中"
    1 -> "17時回ったんで"
    _ -> "システム障害（嘘）"
  }
}

// ---------------------------------------------------------------------------
// リストユーティリティ
// ---------------------------------------------------------------------------

fn clone_at(clones: List(CloneButton), index: Int) -> Result(CloneButton, Nil) {
  case index, clones {
    _, [] -> Error(Nil)
    0, [head, ..] -> Ok(head)
    n, [_, ..tail] -> clone_at(tail, n - 1)
  }
}

fn remove_at_index(clones: List(CloneButton), index: Int) -> List(CloneButton) {
  case index, clones {
    _, [] -> []
    0, [_, ..tail] -> tail
    n, [head, ..tail] -> [head, ..remove_at_index(tail, n - 1)]
  }
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

pub fn view(model: Model) -> Element(Msg) {
  html.main(
    [
      attribute.class(
        "min-h-dvh bg-cream font-sans text-[#4A4A4A] flex flex-col items-center justify-center gap-8 px-4 py-12 overflow-hidden",
      ),
    ],
    [
      header_view(),
      character_view(model),
      dialogue_view(model),
      button_view(model),
      drawing_view(model),
      result_view(model),
    ],
  )
}

fn header_view() -> Element(Msg) {
  html.header([attribute.class("text-center")], [
    html.h1(
      [
        attribute.class(
          "text-4xl font-bold tracking-wider mb-2 bg-gradient-to-r from-pink to-lavender bg-clip-text text-transparent",
        ),
      ],
      [html.text("にょわくじ2026")],
    ),
    html.p([attribute.class("text-sm text-[#9B9B9B] tracking-wide")], [
      html.text("〜 おみくじ、にょわ〜っと 〜"),
    ]),
  ])
}

fn character_view(model: Model) -> Element(Msg) {
  let #(char_text, anim_class) = case model.phase {
    Idle -> #("（ ˘ω˘ ）", "animate-float")
    Evading(Cooperating) -> #("（ ˘ω˘ ）", "animate-float")
    Evading(_) -> #("（ >ω< ）", "animate-shake")
    Drawing(Instant) -> #("（ ˘ᴗ˘ ）", "animate-float")
    Drawing(Spinning) -> #("（ ●ω● ）", "animate-shake")
    Drawing(Paused) -> #("（ ˘ω˘ ）", "animate-breathe")
    Drawing(Reversing) -> #("（ >ω< ）", "animate-shake")
    ShowResult(fortune) ->
      case fortune.mood {
        Furious -> #("（ >﹏< ）", "")
        Grumpy -> #("（ -_- ）", "")
        Neutral -> #("（ ^ω^ ）", "")
        Rested -> #("（ ˘ᴗ˘ ）", "animate-float")
        Sleepy -> #("（ -ω- ）zzZ", "animate-breathe")
      }
  }
  html.div([attribute.class("text-5xl leading-none " <> anim_class)], [
    html.text(char_text),
  ])
}

fn dialogue_view(model: Model) -> Element(Msg) {
  let text = case model.dialogue {
    Some(t) -> t
    None ->
      case model.phase {
        Idle -> "くじ……？にょわ〜……"
        _ -> ""
      }
  }
  case text {
    "" -> html.div([], [])
    _ ->
      html.div(
        [
          attribute.class(
            "bg-white rounded-2xl px-5 py-3 shadow text-sm text-[#4A4A4A] max-w-xs text-center animate-fade-in",
          ),
        ],
        [html.text("💬 " <> text)],
      )
  }
}

fn button_view(model: Model) -> Element(Msg) {
  let normal_btn_class =
    "px-10 py-4 rounded-full bg-gradient-to-r from-pink to-lavender text-white font-bold text-lg shadow-lg hover:scale-105 active:scale-95 transition-all duration-200 cursor-pointer"
  let fixed_btn_class =
    "px-10 py-4 rounded-full bg-gradient-to-r from-pink to-lavender text-white font-bold text-lg shadow-lg cursor-pointer"
  let placeholder =
    html.div([attribute.class("h-14 w-48 opacity-0 pointer-events-none")], [])

  case model.phase {
    ShowResult(_) -> html.div([], [])
    Drawing(_) -> html.div([], [])

    Evading(Dodging(pos, count)) -> {
      let x = int.to_string(float.round(pos.x))
      let y = int.to_string(float.round(pos.y))
      html.div([], [
        placeholder,
        html.button(
          [
            attribute.class(fixed_btn_class),
            attribute.style("position", "fixed"),
            attribute.style("left", x <> "px"),
            attribute.style("top", y <> "px"),
            attribute.style("transition", dodge_transition(count)),
            attribute.style("z-index", "50"),
            event.on_click(ButtonClicked(0)),
            event.on("mouseenter", decode.success(ButtonHovered)),
            event.on("touchstart", decode.success(ButtonTouched)),
          ],
          [html.text("くじを引く")],
        ),
      ])
    }

    Evading(Cloning(clones)) ->
      html.div([], [placeholder, ..render_clones(clones, 0, fixed_btn_class)])

    Evading(Excusing(_, _)) ->
      html.button(
        [
          attribute.class(
            "px-10 py-4 rounded-full bg-gradient-to-r from-[#C8C8C8] to-[#D8D8D8] text-white font-bold text-lg shadow cursor-not-allowed opacity-70",
          ),
          attribute.disabled(True),
        ],
        [html.text("くじを引く")],
      )

    Evading(Camouflaging(pos)) -> {
      let x = int.to_string(float.round(pos.x))
      let y = int.to_string(float.round(pos.y))
      html.div([], [
        placeholder,
        html.button(
          [
            attribute.class(
              "px-10 py-4 rounded-full font-bold text-lg cursor-pointer border-2",
            ),
            attribute.style("position", "fixed"),
            attribute.style("left", x <> "px"),
            attribute.style("top", y <> "px"),
            attribute.style("z-index", "50"),
            attribute.style("background-color", "var(--color-cream)"),
            attribute.style("color", "var(--color-cream)"),
            attribute.style("border-color", "var(--color-cream-dark)"),
            event.on_click(ButtonClicked(0)),
          ],
          [html.text("くじを引く")],
        ),
      ])
    }

    Evading(Cooperating) ->
      html.button(
        [
          attribute.class(normal_btn_class),
          event.on_click(ButtonClicked(0)),
        ],
        [html.text("くじを引く")],
      )

    _ ->
      html.button(
        [
          attribute.class(normal_btn_class),
          event.on_click(ButtonClicked(0)),
          event.on("mouseenter", decode.success(ButtonHovered)),
          event.on("touchstart", decode.success(ButtonTouched)),
        ],
        [html.text("くじを引く")],
      )
  }
}

fn render_clones(
  clones: List(CloneButton),
  index: Int,
  class: String,
) -> List(Element(Msg)) {
  case clones {
    [] -> []
    [head, ..tail] -> [
      render_clone_button(head, index, class),
      ..render_clones(tail, index + 1, class)
    ]
  }
}

fn render_clone_button(
  clone: CloneButton,
  index: Int,
  class: String,
) -> Element(Msg) {
  let x = int.to_string(float.round(clone.pos.x))
  let y = int.to_string(float.round(clone.pos.y))
  html.button(
    [
      attribute.class(class),
      attribute.style("position", "fixed"),
      attribute.style("left", x <> "px"),
      attribute.style("top", y <> "px"),
      attribute.style("z-index", "50"),
      attribute.style("transition", "opacity 0.2s ease"),
      event.on_click(ButtonClicked(index)),
    ],
    [html.text("くじを引く")],
  )
}

fn drawing_view(model: Model) -> Element(Msg) {
  case model.phase {
    Drawing(state) -> {
      let drum_names = ["大吉", "中吉", "小吉", "吉", "末吉", "凶", "大凶", "にょわ吉"]
      let drum_items =
        list.map(drum_names, fn(name) {
          html.div(
            [
              attribute.class(
                "h-14 flex items-center justify-center text-2xl font-bold text-pink",
              ),
            ],
            [html.text(name)],
          )
        })
      let anim_class = case state {
        Spinning -> "animate-drum-spin"
        Reversing -> "animate-drum-reverse"
        Paused -> "animate-drum-pause"
        Instant -> ""
      }
      let inner = html.div([attribute.class(anim_class)], drum_items)

      html.div(
        [attribute.class("flex flex-col items-center gap-3 animate-fade-in")],
        [
          html.div(
            [
              attribute.class(
                "bg-white rounded-2xl shadow-lg overflow-hidden w-40 h-14",
              ),
            ],
            case state {
              Instant -> [
                html.div(
                  [
                    attribute.class(
                      "h-14 flex items-center justify-center text-2xl font-bold text-pink",
                    ),
                  ],
                  [html.text("✨")],
                ),
              ]
              _ -> [inner]
            },
          ),
        ],
      )
    }
    _ -> html.div([], [])
  }
}

fn result_view(model: Model) -> Element(Msg) {
  case model.phase {
    ShowResult(fortune) -> {
      // 機嫌に応じたグラデーション色
      let gradient = case fortune.mood {
        Furious -> "from-[#FF8B8B] to-[#FF6464]"
        Grumpy -> "from-[#A8A8A8] to-[#C0C0C0]"
        Neutral -> "from-pink to-lavender"
        Rested -> "from-[#FFD700] to-[#FFA040]"
        Sleepy -> "from-[#9BB5D4] to-lavender"
      }
      html.div(
        [attribute.class("flex flex-col items-center gap-5 animate-fade-in")],
        [
          html.div(
            [
              attribute.class(
                "bg-white rounded-3xl px-10 py-8 shadow-xl text-center max-w-sm w-full",
              ),
            ],
            [
              html.p(
                [
                  attribute.class(
                    "text-2xl font-bold bg-gradient-to-r "
                    <> gradient
                    <> " bg-clip-text text-transparent mb-3",
                  ),
                ],
                [html.text(fortune.rank)],
              ),
              html.p(
                [attribute.class("text-[#4A4A4A] text-sm leading-relaxed")],
                [html.text(fortune.message)],
              ),
            ],
          ),
          html.button(
            [
              attribute.class(
                "text-sm text-[#9B9B9B] underline underline-offset-2 hover:text-pink transition-colors duration-200 cursor-pointer",
              ),
              event.on_click(PlayAgain),
            ],
            [html.text("もう一回にょわる")],
          ),
        ],
      )
    }
    _ -> html.div([], [])
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// ---------------------------------------------------------------------------
// Effects / FFI wrappers
// ---------------------------------------------------------------------------

fn delay_msg(msg: Msg, ms: Int) -> effect.Effect(Msg) {
  effect.from(fn(dispatch) { set_timeout(fn() { dispatch(msg) }, ms) })
}

@external(javascript, "./nyowa_ffi.mjs", "setTimeoutFn")
fn set_timeout(callback: fn() -> Nil, ms: Int) -> Nil

@external(javascript, "./nyowa_ffi.mjs", "now")
pub fn now() -> Float

@external(javascript, "./nyowa_ffi.mjs", "random")
pub fn random() -> Float

@external(javascript, "./nyowa_ffi.mjs", "getViewportSize")
pub fn get_viewport_size() -> #(Float, Float)
