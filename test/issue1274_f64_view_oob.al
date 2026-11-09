## e2e (#1274) — checked indexing of a slice view LOCAL traps out of range (I11; Types `Slice(T)`
## indexing; CG-7). x86_64 emitted the bounds check only for a `u64`/`u8`-element view local, so an
## out-of-range index into a view of any other element kind read or wrote past the view and ran on.
## A float element.
main := fn() -> u64 {
  t : [f64; 3] = [1.0, 2.0, 3.0]
  xs := t[0..2]
  mut i : usize = 1
  i = i + 1
  u64(xs[i])
}
## expect: trap
