## #1260 control — the same underflow spelled `unchecked (…)` is the defined wrap, so it is NOT the
## overflow diagnostic: the bound folds to the wrapped `usize` 2^64 − 1 (Comptime §2.6 materializes
## the wrap only where it is asked for). A range of 2^64 − 1 iterations is past the unroll budget, so
## the observable is the budget refusal (Comptime §2.2: no silent partial result), never an empty
## loop and never the overflow reject. x86_64 refuses at line 10; the twins trap until #1232.
P := struct { a : u64, b : u64, c : u64 }

main := fn() -> u64 {
  mut n : u64 = 0
  comptime for i in 0 .. unchecked (typeinfo(P).fields.len - 4) { n = n + 1 }
  n + 40
}
## expect: reject "budget exhausted" "never a silent partial result. at line 10 in "
