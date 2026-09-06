## The `unchecked` side of `test/checked_global_struct_field_array_oob.al` and
## `test/checked_global_struct_field_array_write_oob.al` (CT-11 / CG-7, Types 6.4): inside an
## `unchecked` scope the bounds check on an array field of a mutable module-level struct is OMITTED
## on BOTH the read and the write, so neither out-of-range access may trap. Only the CHECK is
## dropped -- the ADDRESS is unchanged, which the in-range rows pin first.
##
## Row 1 -- in-range READ under `unchecked`: still the field's own third element, 30. A wrong-base or
##   off-by-one read cannot produce it; 10 / 20 / 30 / 99 / 55 / 77 are pairwise distinct and
##   non-zero, so an address error surfaces as a distinct wrong exit rather than a silent match.
## Row 2 -- out-of-range READ under `unchecked`: must COMPLETE. Its value is the well-defined
##   consequence of the documented address math -- `LABEL + (off + 3)*8` is the `guard` field -- so
##   the assertion pins that exact word, 99.
## Row 3 -- in-range WRITE under `unchecked`: lands in the array and leaves `guard` alone.
## Row 4 -- out-of-range WRITE under `unchecked`: must COMPLETE, at that same `guard` word, so the
##   read-back is the value just stored, 77.
## A compiler that kept either check here would die of SIGILL (132) instead of reaching any return.
##
## Each failure owns its own code from 100 (#386), no arithmetic combination; the success value is
## 42. Registered `run_x86`: a64/rv64/wasm fail loud on this whole shape today, in range as well out.
G := struct { xs : [u64; 3], guard : u64 }
mut gg := G(xs = [10, 20, 30], guard = 99)
main := fn() -> u64 {
  c : u64 = 2
  if unchecked gg.xs[c] != 30 { return 111 }
  i : u64 = 3
  if unchecked gg.xs[i] != 99 { return 112 }
  b : u64 = 1
  unchecked { gg.xs[b] = 55 }
  if gg.xs[b] != 55 { return 113 }
  if gg.guard != 99 { return 114 }
  unchecked { gg.xs[i] = 77 }
  if gg.guard != 77 { return 115 }
  return 42
}
