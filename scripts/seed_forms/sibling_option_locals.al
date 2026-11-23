## Seed-forms row `sibling_option_locals` (#1886, state `tree`): two locals with the same name and
## different `Option(struct)` types, declared in sibling scopes (here the branches of an `if`/`else`),
## read the second one's payload at the first one's layout on x86_64, so `f(false, 10)` answers 11, not
## 21. Due 42. Workaround: src/ir/build.al:ib_bx_ptr_field names the two locals apart (`npo`, `dpo`).
P := struct { v : u64, s : u64, n : u64 }
S := struct { s : u64, n : u64 }
lp := fn(x : u64) -> Option(P) { Option(P).Some(P(v = x, s = 1, n = 2)) }
ls := fn(x : u64) -> Option(S) { Option(S).Some(S(s = x, n = x + 1)) }
f := fn(b : bool, x : u64) -> u64 {
  mut r : u64 = 0
  if b {
    po : Option(P) = lp(x)
    match po { Some(p) => { r = p.v + p.s + p.n }; None => { r = 77 } }
  } else {
    po : Option(S) = ls(x)
    match po { Some(ps) => { r = ps.s + ps.n }; None => { r = 88 } }
  }
  r
}
main := fn() -> u64 { f(false, 10) + f(true, 1) + 17 }
