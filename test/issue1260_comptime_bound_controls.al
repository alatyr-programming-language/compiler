## #1260 controls — the shapes that must NOT be refused. A `comptime for` bound that stays in range
## unrolls exactly as it did before the guard existed, for both member counts sema now types as a
## `usize`: the `len` of a struct's `fields` table and an array's `n` (the only `n` TypeInfo has —
## `Array{elem, n : usize}`, Stdlib appendix; Comptime §5.1). These ran on `main` before the fix and
## must run unchanged after it, so a guard that fires on any of them is a wrong reject. The array is
## reached through a generic instance, the shape `lib/base/derive.al` uses.
## expect: run 42
P := struct { a : u64, b : u64, c : u64 }

count_less_one := fn(T : type, a : T) -> u64 {
  mut k : u64 = 0
  comptime for q in 0 .. typeinfo(T).n - 1 { k = k + 1 }
  k
}

main := fn() -> u64 {
  mut n : u64 = 0
  comptime for i in 0 .. typeinfo(P).fields.len - 1 { n = n + 1 }
  if n != 2 { return 10 }
  mut m : u64 = 0
  comptime for j in 0 .. typeinfo(P).fields.len { m = m + 1 }
  if m != 3 { return 11 }
  arr : [u64; 3] = [9, 9, 9]
  if count_less_one([u64; 3], arr) != 2 { return 12 }
  42
}
