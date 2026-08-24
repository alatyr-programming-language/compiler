## Checked-mode bounds trap for an AGGREGATE-element frame array (I11 / Types §5, §358). A struct/enum/
## str-element array `[P; N]` was NOT bounds-checked (only scalar/float-element arrays were): its slot's
## `snl` holds the element TYPE span, not the count, so the count is recovered from the reserved filler
## slots (`agg_arr_fill_count / stride`). An out-of-range index now traps deterministically (`cmpq $N;
## jb; ud2` — SIGILL, exit 132), exactly like the scalar case; `unchecked (a[i])` drops the check.
## x86_64-only for now (the check lives in the x86_64 index lowering). Before the fix this SILENTLY read
## out of bounds (returned garbage) — a real I11 gap. `i = 5` on a 2-element `[P; 2]` → trap.
P := struct { x : u64, y : u64 }
main := fn() -> u64 {
  arr := [P(x = 1, y = 2), P(x = 3, y = 4)]
  i : u64 = 5
  return arr[i].x
}
