## e2e / four backends (#672) — a `comptime for` RANGE BOUND written as CONST ARITHMETIC must name
## the same element set on every surface. Comptime §8.3 emits the body once per element and Control
## Flow §5.4/§6 fixes `lo .. hi` as half-open (`lo ≤ i < hi`), so the iteration COUNT is a property
## of the source, not of the selected backend.
##
## Measured on the parent (`20ddb3f`, compiler built from the tree, every rc read outside a pipeline):
## x86_64 `alatyr run` → 42, while aarch64 and riscv64 (`as`/`ld` → qemu) and wasm (`wat2wasm` →
## wasmtime) → 3, i.e. the FIRST const-arithmetic bound below already iterated the wrong number of
## times. Per-shape counts on the parent, x86 against the other three:
##   `0 .. N - 1`   4 vs 0      `0 .. 2 + 2`  4 vs 0      `0 .. M * 3`  6 vs 0
##   `N - 4 .. N`   4 vs 5      `0 - 2 .. 2`  4 vs 2      `0 .. N + 1`  6 vs 0
##   `0 .. N / 2`   2 vs 0      `0 .. N % 3`  2 vs 0
## Each of those compiled clean and exited 0 on all four backends — the programs did not fail, they
## ran a different loop — which is why the cross-target sweeps never saw it: they compare a program
## against its own expected exit status, and there was no wrong exit status to see.
##
## The x86 lower folded these through `global_init_value`; the three emit-side twins
## (`a64_comp_range_bound` / `rv_comp_range_bound` / `wat_comp_range_bound`) absorbed `Expr::Bin`
## into a wildcard and returned their initial `mut r := 0` as if it were the bound.
##
## The first two loops are the CONTROL: a bare literal bound and a bare module-const bound already
## agreed on all four backends before this fix and still do, so a failure in code 1 or 2 says the
## repair broke the shapes it was not aimed at.
N := 5
M := 2

main := fn() -> u64 {
  ## control — literal bound
  mut lit : u64 = 0
  comptime for i in 0 .. 4 { lit = lit + 1 }
  if lit != 4 { return 1 }

  ## control — bare module-const bound
  mut bare : u64 = 0
  comptime for i in 0 .. N { bare = bare + 1 }
  if bare != 5 { return 2 }

  ## const arithmetic in the HI bound: subtraction against a module const
  mut sub : u64 = 0
  comptime for i in 0 .. N - 1 { sub = sub + 1 }
  if sub != 4 { return 3 }

  ## const arithmetic over two literals
  mut add : u64 = 0
  comptime for i in 0 .. 2 + 2 { add = add + 1 }
  if add != 4 { return 4 }

  ## multiplication
  mut mul : u64 = 0
  comptime for i in 0 .. M * 3 { mul = mul + 1 }
  if mul != 6 { return 5 }

  ## const arithmetic in the LO bound (1 .. 5)
  mut lo : u64 = 0
  comptime for i in N - 4 .. N { lo = lo + 1 }
  if lo != 4 { return 6 }

  ## a NEGATIVE lower bound written as a binary subtraction (-2 .. 2); #638's decline sentinel owns
  ## the `-2` unary spelling, which is a different expression shape and is not asserted here
  mut neg : u64 = 0
  comptime for i in 0 - 2 .. 2 { neg = neg + 1 }
  if neg != 4 { return 7 }

  ## addition
  mut plus : u64 = 0
  comptime for i in 0 .. N + 1 { plus = plus + 1 }
  if plus != 6 { return 8 }

  ## division (5 / 2 = 2)
  mut div : u64 = 0
  comptime for i in 0 .. N / 2 { div = div + 1 }
  if div != 2 { return 9 }

  ## remainder (5 % 3 = 2)
  mut rem : u64 = 0
  comptime for i in 0 .. N % 3 { rem = rem + 1 }
  if rem != 2 { return 10 }

  return 42
}
