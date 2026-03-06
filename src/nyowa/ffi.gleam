import lustre/effect
import nyowa/model.{type Msg}

pub fn delay_msg(msg: Msg, ms: Int) -> effect.Effect(Msg) {
  effect.from(fn(dispatch) { set_timeout(fn() { dispatch(msg) }, ms) })
}

@external(javascript, "../nyowa_ffi.mjs", "setTimeoutFn")
pub fn set_timeout(callback: fn() -> Nil, ms: Int) -> Nil

@external(javascript, "../nyowa_ffi.mjs", "now")
pub fn now() -> Float

@external(javascript, "../nyowa_ffi.mjs", "random")
pub fn random() -> Float

@external(javascript, "../nyowa_ffi.mjs", "getViewportSize")
pub fn get_viewport_size() -> #(Float, Float)
