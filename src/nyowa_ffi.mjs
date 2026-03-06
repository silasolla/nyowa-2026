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
  // Node.js では window が存在しないためデフォルト値を返す (テスト環境)
  return [globalThis.innerWidth ?? 375, globalThis.innerHeight ?? 812];
}
