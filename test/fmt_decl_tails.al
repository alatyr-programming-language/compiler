## fmt fixture — three more shapes the AST does not keep. All three used to come back as a DIFFERENT
## program, none of them as a formatting difference:
##   • a COMPOUND assignment `x -= 50` (spec §10) is desugared to `Assign(x, Bin(-, x, 50))`, and the
##     `:=`-vs-`=` probe reads the source at the name, sees `-=` rather than `=`, and concluded "first
##     binding" — so fmt re-emitted `x := x - 50`, SHADOWING the mutable local instead of updating it.
##   • a `when` guard written after an aggregate's closing BRACE (Comptime §7.1/§9, CT-5) was dropped,
##     so two complementary arch-gated `Cfg` decls came back as an unguarded duplicate.
##   • `NonZero := u32.require(is_nonzero)` — the UFCS spelling of a validity contract (Types §8.1) —
##     kept only the bare PATH span `u32`, so the contract silently vanished. The alias RHS is now
##     copied verbatim to end of line, which is exact for every alias form.
## Returns 42.
Cfg := struct { a : u64, b : u64 } when target.arch == Arch.x86_64
Cfg := struct { a : u64, b : u64, c : u64, d : u64 } when target.arch == Arch.aarch64

is_nonzero := fn(v : u32) -> bool { return v != 0 }

NonZero := u32.require(is_nonzero)

main := fn() -> u64 {
  n := NonZero(5)
  if size(Cfg) != 16 { return 1 }
  mut x := 100
  x -= 50
  x *= 3
  x /= 5
  x += 12
  return x
}
