## e2e (#1274) — checked indexing of a slice view LOCAL traps out of range (I11; Types `Slice(T)`
## indexing; CG-7). x86_64 emitted the bounds check only for a `u64`/`u8`-element view local, so an
## out-of-range index into a view of any other element kind read or wrote past the view and ran on.
## A pointer element, which used to crash (SIGSEGV) instead of trapping.
P := struct { a : u64, b : u64 }
main := fn() -> u64 {
  mut q : P = P(a = 1, b = 2)
  t : [ptr(mut P); 3] = [ptr(mut q), ptr(mut q), ptr(mut q)]
  xs := t[0..2]
  mut i : usize = 1
  i = i + 1
  deref(xs[i]).b
}
## expect: trap
