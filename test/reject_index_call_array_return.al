## e2e (build_reject_has) — a direct index of a fixed WORD-array call result remains outside the
## bounded P1-BYTES ABI. The lower must reject this unsupported call-result place with a located,
## intentional diagnostic; it must not treat the return registers as an inline array and silently
## produce a wrong word. The u8 shape has its own positive direct regression.
build := fn() -> [u64; 4] {
  mut t : [u64; 4] = [0; 4]
  t[2] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 2
  u64(build()[k])
}
