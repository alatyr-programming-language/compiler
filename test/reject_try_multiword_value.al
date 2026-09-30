## Issue #752 — the VALUE of `?` over a multi-word Ok payload used where only one word can arrive
## (here a by-value struct argument). The binding and field forms read the payload's words from the
## return registers; this position cannot, and it used to pass word 0 as the struct — a segfault or,
## with a pointer-shaped first word, a silent wrong value. It is refused, located, before any emit.
T := struct { k : u64, a : u64, b : u64 }
f := fn(n : u64) -> Result(T, u64) { Result(T, u64).Ok(T(k = n, a = 20, b = 22)) }
use := fn(t : T) -> u64 { t.a + t.b }
g := fn() -> Result(u64, u64) { Result(u64, u64).Ok(use(f(1)?)) }
main := fn() -> u64 {
  match g() { Result::Ok(v) => { return v } Result::Err(e) => { return 1 } }
  0
}
