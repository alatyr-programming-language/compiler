## #682 / #923 — a `comptime for` bound that NAMES a module const whose OWN initializer is
## arithmetic must name the same element set on every backend. Comptime §8.3 emits the body once per
## element and Control Flow §5.4/§6 fixes `lo .. hi` as half-open (`lo <= i < hi`), so the iteration
## COUNT is a property of the source, not of the backend that compiles it.
##
## This is the OTHER half of #672. #672 gave the three emit twins a `Bin` arm, so arithmetic written
## AT THE BOUND (`0 .. N - 1`) folds everywhere. Here the arithmetic is INSIDE the const's
## initializer, so the bound expression itself is a plain `Expr::Var` and never reaches that arm:
## the twins resolved the name, read its value with `lower_layout::ex_value_init`, and that leaf
## answered 0 for a `Var` — so `B := A + 1` folded to `0 + 1`.
##
## Measured on `a02baeb` (compiler built from the tree, every rc read outside a pipeline):
##   x86_64 -> 42      aarch64 -> V2      riscv64 -> V2      wasm -> V2
## V2 is the first guard below, i.e. `sub` iterated 0 times instead of 4 — the loop ran a different
## number of times with a clean compile and no diagnostic, which is why the cross-target sweeps never
## saw it: they compare a program against its OWN expected exit status.
##
## The first two loops are the CONTROL: a literal bound and a bare const bound already agreed on all
## four backends before this fix and still do, so a failure in code 1 or 2 says the repair broke the
## shapes it was not aimed at.
A := 3
B := A + 1        ## a const whose initializer is arithmetic — the shape that folded to 0 on the twins
C := B * 2        ## two hops deep (B -> A), so the chase is not one level
D := 10 - C       ## arithmetic with the const on the LEFT

main := fn() -> u64 {
  ## control — literal bound
  mut lit : u64 = 0
  comptime for i in 0 .. 4 { lit = lit + 1 }
  if lit != 4 { return 1 }

  ## control — bare module-const bound (a literal initializer, already agreed everywhere)
  mut bare : u64 = 0
  comptime for i in 0 .. A { bare = bare + 1 }
  if bare != 3 { return 2 }

  ## the defect: a bound naming a const whose initializer is `A + 1`
  mut sub : u64 = 0
  comptime for i in 0 .. B { sub = sub + 1 }
  if sub != 4 { return 3 }

  ## two hops: C := B * 2 := (A + 1) * 2 = 8
  mut hop : u64 = 0
  comptime for i in 0 .. C { hop = hop + 1 }
  if hop != 8 { return 4 }

  ## the const on the left of the operator: D := 10 - C = 2
  mut left : u64 = 0
  comptime for i in 0 .. D { left = left + 1 }
  if left != 2 { return 5 }

  ## a computed LO bound over such a const, not just the HI bound
  mut lo : u64 = 0
  comptime for i in B .. C { lo = lo + 1 }
  if lo != 4 { return 6 }

  ## NOT asserted: reading such a const in a RUNTIME expression (`if B + C + D != 14`). Measured on
  ## this fix, that shape traps on the twins (`brk #0` / `ebreak` / `(unreachable)`, V133/V134) while
  ## x86_64 answers — a DIFFERENT path (the emitter's `Expr::Var` read, not `*_comp_range_bound`) and
  ## a different issue. Asserting it here would make this fixture red for a gap it does not claim.
  return 42
}
