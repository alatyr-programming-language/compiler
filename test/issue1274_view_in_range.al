## e2e (#1274) — checked indexing of a slice view LOCAL traps out of range (I11; Types `Slice(T)`
## indexing; CG-7). x86_64 emitted the bounds check only for a `u64`/`u8`-element view local, so an
## out-of-range index into a view of any other element kind read or wrote past the view and ran on.
## The in-range control: the LAST index of each kind's view still reads the right element, so the
## new check does not trap one short. Each check returns its own code; 42 is a pass.
P := struct { a : u64, b : u64 }
E := enum { A(u64), B }
main := fn() -> u64 {
  mut i : usize = 0
  i = i + 1
  t : [P; 3] = [P(a = 1, b = 2), P(a = 3, b = 4), P(a = 5, b = 6)]
  xs := t[1..3]
  if xs[i].b != 6 { return 1 }
  p := xs[i]
  if p.a != 5 { return 2 }
  ys : Slice(P) = t[0..2]
  if ys[i].b != 4 { return 3 }
  es : [E; 2] = [E.B, E.A(7)]
  ev := es[0..2]
  mut got : u64 = 0
  match ev[i] {
    E::A(v) => { got = v }
    E::B => {}
  }
  if got != 7 { return 4 }
  ss : [str; 2] = ["a", "bc"]
  sv := ss[0..2]
  if sv[i].len != 2 { return 5 }
  mut q : P = P(a = 8, b = 9)
  ps : [ptr(mut P); 2] = [ptr(mut q), ptr(mut q)]
  pv := ps[0..2]
  if deref(pv[i]).b != 9 { return 6 }
  fs : [f64; 2] = [1.0, 2.0]
  fv := fs[0..2]
  if u64(fv[i]) != 2 { return 7 }
  mut w : [P; 2] = [P(a = 1, b = 2), P(a = 3, b = 4)]
  wv := w[0..2]
  wv[i].b = 11
  if w[1].b != 11 { return 8 }
  42
}
## expect: run 42
