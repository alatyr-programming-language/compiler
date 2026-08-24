## e2e (Shape B — a nested MATCH on an aggregate scrutinee bound by an enclosing arm). The outer
## `match o` binds `x` (an `Inner` enum with a multi-word payload) in the `Outer.A(x)` arm; the inner
## `match x` must read the RIGHT payload words, not a truncated / clobbered copy. Each by-ref enum
## scrutinee materializes into its own nested-match scratch level, so the inner match sees the whole
## `Inner.V(40, 2)` payload. Returns 40 + 2 = 42. Locks that a nested aggregate match is sound.
Inner := enum { N, V(u64, u64) }
Outer := enum { A(Inner), B }
main := fn() -> u64 {
  o : Outer = Outer.A(Inner.V(40, 2))
  match o {
    Outer.A(x) => {
      match x {
        Inner.V(p, q) => { return p + q }
        Inner.N => { return 1 }
      }
    }
    Outer.B => { return 2 }
  }
  return 3
}
