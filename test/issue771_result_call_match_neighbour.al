## Issue #771 — a `match` written directly on a call that returns `Result(S, E)` with a 3- or 4-word
## struct payload. The match scratch was sized from enum DECLARATIONS alone (`Ok(T)` counts as one word
## there), so it held two words, and the words past it were stored over the locals below it. Each
## function here keeps a live local next to the scratch. On the parent every one of them returned a
## wrong value with a clean build (this program exited 1 instead of 42): the value form, the 4-word
## payload, the same match in a `while` (the loop counter was reset on every pass; the `g` guard keeps
## the parent from hanging), the statement form, and a match nested inside another one's arm.
S3 := struct { f0 : u64, f1 : u64, f2 : u64 }
S4 := struct { f0 : u64, f1 : u64, f2 : u64, f3 : u64 }
r3 := fn(x : u64) -> Result(S3, u64) { Result(S3, u64).Ok(S3(f0 = x, f1 = x + 1, f2 = x + 2)) }
r4 := fn(x : u64) -> Result(S4, u64) { Result(S4, u64).Ok(S4(f0 = x, f1 = x + 1, f2 = x + 2, f3 = x + 3)) }
value3 := fn() -> u64 {
  mut v : u64 = 0
  mut c : u64 = 0
  v = v + (match r3(1) { Result::Ok(q) => { q.f0 + q.f1 + q.f2 } Result::Err(e) => { 100 } })
  v + c
}
value4 := fn() -> u64 {
  mut v : u64 = 0
  mut c : u64 = 0
  v = v + (match r4(1) { Result::Ok(q) => { q.f3 } Result::Err(e) => { 100 } })
  v + c
}
looped := fn() -> u64 {
  mut n : u64 = 0
  mut g : u64 = 0
  mut c : u64 = 0
  while c < 5 and g < 20 {
    n = n + (match r3(1) { Result::Ok(q) => { q.f2 } Result::Err(e) => { 100 } })
    c = c + 1
    g = g + 1
  }
  n + g
}
stmt := fn() -> u64 {
  mut t : u64 = 0
  mut c : u64 = 0
  match r4(2) { Result::Ok(q) => { t = q.f0 + q.f3 } Result::Err(e) => { t = 100 } }
  t + c
}
nested := fn() -> u64 {
  mut w : u64 = 0
  match r3(10) {
    Result::Ok(q) => {
      inner := match r4(20) { Result::Ok(p) => { p.f3 } Result::Err(e) => { 0 } }
      w = q.f0 + q.f2 + inner
    }
    Result::Err(e) => { w = 100 }
  }
  w
}
main := fn() -> u64 {
  if value3() != 6 { return 1 }
  if value4() != 4 { return 2 }
  if looped() != 20 { return 3 }
  if stmt() != 7 { return 4 }
  if nested() != 45 { return 5 }
  42
}
