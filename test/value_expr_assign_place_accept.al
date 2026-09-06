## e2e (#428) — the load-bearing half of the value-expression store reject: the PLACE forms it must
## NOT false-reject. The new recognizer scans the statement head twice — once as Grammar §3.3's
## `place`, once as the wider postfix chain — and only refuses when the two DISAGREE, so every legal
## spelling below has to keep parsing exactly as it did. A broad parser fence regressed ~90 stdlib
## tests earlier in this project, which is why each of these is a proven accept, not a tuning matter.
##
## Covers, in both the plain `=` and a compound-operator spelling:
##   1. an array element `a[i]`, indexed by a local
##   2. a struct field `s.fa`
##   3. an array element of a struct field `s.gb[1]` — a `]` postfix over a `.` postfix
##   4. a tuple component `t.0` — the numeric projection, not a field name
##   5. a dereference `deref(p)` — the one place root that legitimately carries a `(`
## The qualified path target `geo::G = …` / `geo::G += …` / `geo::TAB[2] = …` needs a second module,
## so it is measured by the existing `module_global_qualified` package row rather than duplicated here.
##
## Expected exit: 42 (every store agrees). A failure exits 100 + the check's 1-based index, so the
## first disagreement is named rather than folded into an arithmetic total.
##
## x86_64 = aarch64 = riscv64 = 42; the WASM backend traps (134) on the struct-field and pointer-store
## halves. That trap is NOT this change: measured identically on the parent (`d18fb3f`) for the same
## two constructs in isolation, and it is the same pre-existing non-x86 store gap
## compound_assign_place_deep.al already records (wasm 134, aarch64/riscv64 133). The corpus manifest
## carries the row; the e2e `run` assertion is x86_64, which is where every place form is complete.
S := struct { fa : u64, gb : [u64; 2] }

thru := fn(p : ptr(mut u64)) -> u64 {
  deref(p) = 6
  deref(p) -= 2
  return 0
}

main := fn() -> u64 {
  mut bad : u64 = 0
  mut a : [u64; 3] = [10, 100, 30]
  i : usize = 1
  a[i] = 7
  a[i] += 5
  if bad == 0 and a[i] != 12 { bad = 1 }
  mut s := S(fa = 1, gb = [3, 4])
  s.fa = 9
  s.fa *= 2
  if bad == 0 and s.fa != 18 { bad = 2 }
  s.gb[1] = 5
  s.gb[1] |= 2
  if bad == 0 and s.gb[1] != 7 { bad = 3 }
  mut t := (3, 4)
  t.0 = 11
  t.0 ^= 5
  if bad == 0 and t.0 != 14 { bad = 4 }
  mut w : u64 = 0
  z := thru(ptr(mut w))
  if bad == 0 and w != 4 { bad = 5 }
  if bad == 0 and z != 0 { bad = 6 }
  if bad != 0 { return 100 + bad }
  return 42
}
