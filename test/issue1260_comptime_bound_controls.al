## #1260 controls — the shapes that must NOT be refused. A `comptime for` bound that stays in range
## unrolls exactly as it did before the guard existed, at both widths the guard can now judge. These
## ran on `main` before the fix and must run unchanged after it, so a guard that fires on either is a
## wrong reject. Measured on both trees: identical.
## expect: run 42
P := struct { a : u64, b : u64, c : u64 }

main := fn() -> u64 {
  mut n : u64 = 0
  comptime for i in 0 .. typeinfo(P).fields.len - 1 { n = n + 1 }
  if n != 2 { return 10 }
  mut m : u64 = 0
  comptime for j in 0 .. typeinfo(P).fields.len { m = m + 1 }
  if m != 3 { return 11 }
  mut k : u64 = 0
  comptime for q in 0 .. typeinfo(P).n { k = k + 1 }
  if k != 3 { return 12 }
  42
}
