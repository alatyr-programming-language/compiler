## e2e: a multi-word AGGREGATE payload in a generic enum — the capability whose absence crashed
## `check`/sema (a truncated `Result(Ty, …)` payload). Exercises the whole path end to end: a
## generic `Result(T, E)` instantiated with a 3-word STRUCT `Ty` (Ok) and a multi-word ENUM `CE`
## (Err); constructing `Ok(Ty(…))` (stores all payload words), returning it across a call (word 0
## in the 2-word return convention), and matching `Ok(s)` binding `s` as an aggregate read by-value
## `s.tag`. `Ok` carries tag 42, and the `Err` arm returns 1, so a correct Ok-path run exits 42.
Result := fn(T : type, E : type) -> type { enum { Ok(T), Err(E) } }
Ty := struct { tag : u64, ns : usize, nl : usize }
CE := enum { Unbound(usize, usize), Mismatch(usize, usize) }
mk := fn(fail : usize) -> Result(Ty, CE) {
  if fail == 1 { return Result(Ty, CE).Err(CE.Unbound(7, 8)) }
  Result(Ty, CE).Ok(Ty(tag = 42, ns = 0, nl = 0))
}
main := fn() -> u64 {
  r := mk(0)
  match r {
    Result::Ok(s) => { u64(s.tag) }
    Result::Err(e) => { 1 }
  }
}
