## e2e (#1274) — checked indexing of a slice view LOCAL traps out of range (I11; Types `Slice(T)`
## indexing; CG-7). x86_64 emitted the bounds check only for a `u64`/`u8`-element view local, so an
## out-of-range index into a view of any other element kind read or wrote past the view and ran on.
## An enum element.
E := enum { A(u64), B }
main := fn() -> u64 {
  t : [E; 3] = [E.A(1), E.A(2), E.A(3)]
  xs := t[0..2]
  mut i : usize = 1
  i = i + 1
  match xs[i] {
    E::A(v) => v,
    E::B => 9,
  }
}
## expect: trap
