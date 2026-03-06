import gleam/float
import gleam/int
import gleam/list
import gleam/result
import nyowa/content
import nyowa/model.{type Fortune, type Mood}

/// evade_count と放置時間 (ms) から機嫌を決定する
/// 優先度: Sleepy > Rested > Furious > Grumpy > Neutral
/// 「待った」事実は「追い回した」事実より優先される
pub fn determine_mood(evade_count: Int, idle_ms: Float) -> Mood {
  let idle_s = idle_ms /. 1000.0
  case idle_s >=. 120.0 {
    True -> model.Sleepy
    False ->
      case idle_s >=. 30.0 {
        True -> model.Rested
        False ->
          case evade_count >= 6 {
            True -> model.Furious
            False ->
              case evade_count >= 3 {
                True -> model.Grumpy
                False -> model.Neutral
              }
          }
      }
  }
}

/// Mood と乱数 (0.0 〜 1.0) からおみくじを選ぶ
pub fn select_fortune(mood: Mood, rand: Float) -> Fortune {
  let pool = fortune_pool(mood)
  let size = list.length(pool)
  let idx = float.truncate(rand *. int.to_float(size)) |> int.min(size - 1)
  let #(rank, message) =
    list.drop(pool, idx) |> list.first() |> result.unwrap(#("吉", "にょわ……"))
  model.Fortune(rank: rank, message: message, mood: mood)
}

fn fortune_pool(mood: Mood) -> List(#(String, String)) {
  case mood {
    model.Furious -> content.furious_fortunes
    model.Grumpy -> content.grumpy_fortunes
    model.Neutral -> content.neutral_fortunes
    model.Rested -> content.rested_fortunes
    model.Sleepy -> content.sleepy_fortunes
  }
}
