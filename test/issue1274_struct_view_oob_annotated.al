## e2e (#1274) — checked indexing of a slice view LOCAL traps out of range (I11; Types `Slice(T)`
## indexing; CG-7). x86_64 emitted the bounds check only for a `u64`/`u8`-element view local, so an
## out-of-range index into a view of any other element kind read or wrote past the view and ran on.
## The annotated spelling, `xs : Slice(P) = t[0..2]` (#1182).
P := struct { a : u64, b : u64 }
main := fn() -> u64 {
  t : [P; 3] = [P(a = 1, b = 2), P(a = 3, b = 4), P(a = 5, b = 6)]
  xs : Slice(P) = t[0..2]
  mut i : usize = 1
  i = i + 1
  xs[i].b
}
## expect: trap
