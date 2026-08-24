## e2e regression (ROADMAP §6 ptr-typing): match arms with 2+ payload bindings AND an aggregate
## payload — the exact shapes that crashed when `Arm.binds_head` / `Bind.next` became `ptr(mut Bind)`.
## A `Bind`-list walk read through a FIELD-READ local (`bnd := am.binds_head`, then `deref(bnd)`) does
## NOT resolve the pointee struct (only a ptr-to-struct PARAM gets `ek = 7`), so the whole-`Bind`
## aggregate copy mis-lowered to a 1-word scalar and `bind.next` read garbage → a wild-pointer deref
## in `emit_match_stmt`. The fix routes every Bind read through the typed `bind_ns`/`bind_nl`/`bind_next`
## accessors (a `p : ptr(mut Bind)` param). Two scalar bindings, three scalar bindings, and a single
## STRUCT-payload binding each exercise a different arm of the walk; all three must land on 42.
E := enum { Pair(u64, u64), Triple(u64, u64, u64), None }
Pt := struct { x : u64, y : u64 }
S := enum { P(Pt), Q }

sum_e := fn(e : E) -> u64 {
  match e {
    E::Pair(a, b) => { return a + b }
    E::Triple(a, b, c) => { return a + b + c }
    E::None => { return 0 }
  }
}

main := fn() -> u64 {
  two := sum_e(E.Pair(40, 2))          ## 2 bindings   -> 42
  three := sum_e(E.Triple(10, 20, 12)) ## 3 bindings   -> 42
  s := S.P(Pt(x = 40, y = 2))
  agg := match s {                      ## aggregate payload binding `pt`
    S::P(pt) => { pt.x + pt.y }
    S::Q => { 0 }
  }
  if two == 42 and three == 42 and agg == 42 { return 42 }
  return 1
}
