## DEFER (Control Flow §9.3) — the EXIT VALUE is computed BEFORE the cleanups run. A `defer` that
## mutates state the exit expression reads must not change what the fn hands back: the value is
## evaluated, THEN the pending actions drain, THEN the (already-computed) value is returned. Covers
## both exit spellings — a TAIL expression (`tailform`) and an explicit `return` (`retform`).
## `tailform` yields A+1 with A still 0 -> 1, and only then sets A = 9; `retform(2)` yields B+2 with B
## still 0 -> 2, and only then sets B = 5. `A*4 + B + r1 + r2` = 36 + 5 + 1 + 2 = 44. Were the drain to
## run FIRST, r1 would be 10 and r2 7 -> 58; were the cleanups DROPPED, A and B would stay 0 -> 3.
## The answer stays < 126 (the WASM sweep's WASI `proc_exit` accepts only [0,126)).
mut A : u64 = 0
mut B : u64 = 0
seta := fn() -> u64 { A = 9 ; 0 }
setb := fn() -> u64 { B = 5 ; 0 }

tailform := fn() -> u64 {
  defer seta()
  A + 1
}

retform := fn(x : u64) -> u64 {
  defer setb()
  return B + x
}

main := fn() -> u64 {
  r1 := tailform()
  r2 := retform(2)
  return A * 4 + B + r1 + r2
}
