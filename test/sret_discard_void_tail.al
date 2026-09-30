## #714 residual: a wide-SRET call as the TRAILING expression of a VOID fn is discarded exactly like a
## statement-position one, and the callee still writes its whole result through the hidden pointer.
## On aarch64 `side`'s trailing `mk(1)` went out with x8 holding whatever was there (SIGSEGV, 139)
## while `sret_discard_statement` had already been fixed for the statement form.
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }

mk := fn(n : u64) -> S9 {
  return S9(a = n, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8, i = 9)
}

side := fn() { mk(1) }

main := fn() -> u64 {
  side()
  d := mk(1)
  return d.h + 34
}
