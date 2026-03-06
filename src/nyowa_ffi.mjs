export function setTimeoutFn(callback, ms) {
  globalThis.setTimeout(callback, ms);
}

export function now() {
  return Date.now();
}

export function random() {
  return Math.random();
}

export function getViewportSize() {
  return [globalThis.innerWidth, globalThis.innerHeight];
}
