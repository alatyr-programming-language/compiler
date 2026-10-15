## e2e — IR slice 3d: an aggregate argument crosses a call as the ADDRESS of a caller-owned copy
## (docs/ir.md §3.7), and that convention is the one every legacy emitter already uses for a struct
## argument, so an IR-built function and a legacy-emitted one call each other in BOTH directions with the
## same layout (docs/ir-slice-3.md Q4: proved here, not assumed).
##
## `lg_*` keep an `Option(u64)` local — an enum, slice 4's construct — so the shared IR refuses them and
## they stay LEGACY-emitted on the twins; `take` and `pass` are IR-built (`alatyr ir` reports `Built`).
##   * IR -> legacy: `main` (IR) passes a local struct and a literal to `lg_take` (legacy);
##   * legacy -> IR: `lg_call` (legacy) passes a literal to `take` (IR);
##   * IR -> IR through a by-reference parameter passed on: `pass` hands its parameter to `take`,
##     which reads a COPY (`pass` mutating its own local afterwards cannot reach `take`'s value);
## The values are non-negative on purpose: this fixture is about the convention, and a negative field
## divided by the LEGACY wasm emitter still divides unsigned (#765, pinned by `ir_struct_field_signed`).
## Each check returns its own code on failure; 42 when all hold, on all four backends.
S := struct { a : i64, b : i64, c : i64 }

take := fn(s : S) -> i64 { return s.a / 4 + s.b + s.c }

pass := fn(s : S, k : i64) -> i64 {
  mut t := s
  r := take(t)
  t.b = 1000
  return r + k + t.b - 1000
}

lg_take := fn(s : S) -> i64 {
  w : Option(u64) = Option(u64).Some(1)
  return s.a - s.c
}

lg_call := fn() -> i64 {
  w : Option(u64) = Option(u64).Some(1)
  return take(S(a = 40, b = 7, c = 3))
}

main := fn() -> i64 {
  s := S(a = 40, b = 7, c = 3)
  if take(s) != 20 { return 1 }
  if lg_take(s) != 37 { return 2 }
  if lg_take(S(a = 10, b = 0, c = 4)) != 6 { return 3 }
  if lg_call() != 20 { return 4 }
  if pass(s, 5) != 25 { return 5 }
  if s.b != 7 { return 6 }
  42
}
