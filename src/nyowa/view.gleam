import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import nyowa/content
import nyowa/evasion
import nyowa/model.{type Model, type Msg}

pub fn view(m: Model) -> Element(Msg) {
  html.main(
    [
      attribute.class(
        "min-h-dvh bg-cream font-sans text-body flex flex-col items-center justify-center gap-8 px-4 py-12 overflow-hidden",
      ),
    ],
    [
      header_view(),
      character_view(m),
      dialogue_view(m),
      button_view(m),
      drawing_view(m),
      result_view(m),
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
      [html.text(content.app_title)],
    ),
    html.p([attribute.class("text-sm text-muted tracking-wide")], [
      html.text(content.app_subtitle),
    ]),
  ])
}

fn character_view(m: Model) -> Element(Msg) {
  let #(char_text, anim_class) = case m.phase {
    model.Idle -> #(content.char_calm, "animate-float")
    model.Evading(model.Cooperating) -> #(content.char_calm, "animate-float")
    model.Evading(_) -> #(content.char_tense, "animate-shake")
    model.Drawing(model.Instant) -> #(content.char_happy, "animate-float")
    model.Drawing(model.Spinning) -> #(content.char_focused, "animate-shake")
    model.Drawing(model.Paused) -> #(content.char_calm, "animate-breathe")
    model.Drawing(model.Reversing) -> #(content.char_tense, "animate-shake")
    model.ShowResult(fortune) ->
      case fortune.mood {
        model.Furious -> #(content.char_upset, "")
        model.Grumpy -> #(content.char_flat, "")
        model.Neutral -> #(content.char_cheerful, "")
        model.Rested -> #(content.char_happy, "animate-float")
        model.Sleepy -> #(content.char_drowsy, "animate-breathe")
      }
  }
  html.div([attribute.class("text-5xl leading-none " <> anim_class)], [
    html.text(char_text),
  ])
}

fn dialogue_view(m: Model) -> Element(Msg) {
  let text = case m.dialogue {
    Some(t) -> t
    None ->
      case m.phase {
        model.Idle -> content.idle_default
        _ -> ""
      }
  }
  case text {
    "" -> element.none()
    _ ->
      html.div(
        [
          attribute.class(
            "bg-white rounded-2xl px-5 py-3 shadow text-sm text-body max-w-xs text-center animate-fade-in",
          ),
        ],
        [html.text(content.dialogue_prefix <> text)],
      )
  }
}

fn button_view(m: Model) -> Element(Msg) {
  let normal_btn_class =
    "px-10 py-4 rounded-full bg-gradient-to-r from-pink to-lavender text-white font-bold text-lg shadow-lg hover:scale-105 active:scale-95 transition-all duration-200 cursor-pointer"
  let fixed_btn_class =
    "px-10 py-4 rounded-full bg-gradient-to-r from-pink to-lavender text-white font-bold text-lg shadow-lg cursor-pointer"
  let placeholder =
    html.div([attribute.class("h-14 w-48 opacity-0 pointer-events-none")], [])

  case m.phase {
    model.ShowResult(_) -> element.none()
    model.Drawing(_) -> element.none()

    model.Evading(model.Dodging(pos, count)) -> {
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
            attribute.style("transition", evasion.dodge_transition(count)),
            attribute.style("z-index", "50"),
            event.on_click(model.ButtonClicked(0)),
            event.on("mouseenter", decode.success(model.ButtonHovered)),
            event.on("touchstart", decode.success(model.ButtonTouched)),
          ],
          [html.text(content.draw_button_label)],
        ),
      ])
    }

    model.Evading(model.Cloning(clones)) ->
      html.div([], [placeholder, ..render_clones(clones, 0, fixed_btn_class)])

    model.Evading(model.Excusing(_, _)) ->
      html.button(
        [
          attribute.class(
            "px-10 py-4 rounded-full bg-gradient-to-r from-disabled-from to-disabled-to text-white font-bold text-lg shadow cursor-not-allowed opacity-70",
          ),
          attribute.disabled(True),
        ],
        [html.text(content.draw_button_label)],
      )

    model.Evading(model.Camouflaging(pos)) -> {
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
            event.on_click(model.ButtonClicked(0)),
          ],
          [html.text(content.draw_button_label)],
        ),
      ])
    }

    model.Evading(model.Cooperating) ->
      html.button(
        [
          attribute.class(normal_btn_class),
          event.on_click(model.ButtonClicked(0)),
        ],
        [html.text(content.draw_button_label)],
      )

    _ ->
      html.button(
        [
          attribute.class(normal_btn_class),
          event.on_click(model.ButtonClicked(0)),
          event.on("mouseenter", decode.success(model.ButtonHovered)),
          event.on("touchstart", decode.success(model.ButtonTouched)),
        ],
        [html.text(content.draw_button_label)],
      )
  }
}

fn render_clones(
  clones: List(model.CloneButton),
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
  clone: model.CloneButton,
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
      event.on_click(model.ButtonClicked(index)),
    ],
    [html.text(content.draw_button_label)],
  )
}

fn drawing_view(m: Model) -> Element(Msg) {
  case m.phase {
    model.Drawing(state) -> {
      let drum_items =
        list.map(content.drum_names, fn(name) {
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
        model.Spinning -> "animate-drum-spin"
        model.Reversing -> "animate-drum-reverse"
        model.Paused -> "animate-drum-pause"
        model.Instant -> ""
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
              model.Instant -> [
                html.div(
                  [
                    attribute.class(
                      "h-14 flex items-center justify-center text-2xl font-bold text-pink",
                    ),
                  ],
                  [html.text(content.instant_icon)],
                ),
              ]
              _ -> [inner]
            },
          ),
        ],
      )
    }
    _ -> element.none()
  }
}

fn result_view(m: Model) -> Element(Msg) {
  case m.phase {
    model.ShowResult(fortune) -> {
      let gradient = case fortune.mood {
        model.Furious -> "from-furious-from to-furious-to"
        model.Grumpy -> "from-grumpy-from to-grumpy-to"
        model.Neutral -> "from-pink to-lavender"
        model.Rested -> "from-rested-from to-rested-to"
        model.Sleepy -> "from-sleepy-from to-lavender"
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
              html.p([attribute.class("text-body text-sm leading-relaxed")], [
                html.text(fortune.message),
              ]),
            ],
          ),
          html.button(
            [
              attribute.class(
                "text-sm text-muted underline underline-offset-2 hover:text-pink transition-colors duration-200 cursor-pointer",
              ),
              event.on_click(model.PlayAgain),
            ],
            [html.text(content.play_again_label)],
          ),
        ],
      )
    }
    _ -> element.none()
  }
}
