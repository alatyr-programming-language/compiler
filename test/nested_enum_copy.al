## e2e: copying an enum-typed MATCH PAYLOAD binding to a local, then matching that local (destructure then
## re-match). `Outer::Wrap(i)` binds `i` as the inner `Inner` enum; `j := i` formerly bound `j` as a SCALAR
## (collect_slots did not type the payload binding — only emit_match aliased it), so `match j` read word 0
## → the wrong arm / 0. Now collect_slots binds a single struct/enum-typed payload binding as a real
## aggregate slot, so `j := i` infers `Inner` and `match j` dispatches correctly. `Inner.X(42)` → 42.
Inner := enum { X(u64), Y }
Outer := enum { Wrap(Inner), Empty }
main := fn() -> u64 {
  o := Outer.Wrap(Inner.X(42))
  match o {
    Outer::Wrap(i) => {
      j := i
      match j { Inner::X(v) => { return v } Inner::Y => { return 1 } }
    }
    Outer::Empty => { return 2 }
  }
}
