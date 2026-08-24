## e2e (build + run, expect 42) — the POSITIVE control for the UFCS `check` two-pass fix. Every call
## shape the widened `check` now SEES must still be accepted AND still lower to the same program: a UFCS
## call over a simple-`Var` receiver (`v.bump(41)`), one taking a `str` (`v.tag("ok")`), a nullary one
## (`v.get()`), a UFCS call feeding another's argument, and — the shape the enum table exists to keep
## apart — a real enum-variant construction `E.B(7)` over the SAME dotted syntax. Guards against the
## opposite failure mode of `reject_ufcs_*`: a `check` that rejects working code.
V := struct { n : u64 }

E := enum { A, B(u64) }

bump := fn(v : V, k : u64) -> u64 { v.n + k }

tag := fn(v : V, s : str) -> u64 { v.n + s.len }

get := fn(v : V) -> u64 { v.n }

payload := fn(e : E) -> u64 {
  match e {
    E::A => { 0 }
    E::B(w) => { w }
  }
}

main := fn() -> u64 {
  v := V(n = 1)
  a := v.bump(41)            ## 42
  b := v.tag("ok")           ## 1 + 2 = 3
  c := v.get()               ## 1
  d := v.bump(v.get())       ## 1 + 1 = 2  (a UFCS call as a UFCS call's argument)
  e := payload(E.B(7))       ## 7  — a REAL enum-variant ctor over the same `X.Y(z)` syntax
  a + b + c + d + e - 13     ## 42 + 3 + 1 + 2 + 7 = 55, less 13 = 42
}
