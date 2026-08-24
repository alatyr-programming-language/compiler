## Checked-mode array bounds trap (I11 / Types §5, §358). A static-length frame array `[T; N]` is
## compiler-emitted `at(a,i)`: in a checked context (the default) an out-of-range index traps
## deterministically (`cmpq $N; jb; ud2` — SIGILL, exit 132); `unchecked (a[i])` drops the check and
## reads raw. `N` is a compile-time value the compiler knows from the array's type. x86_64-only for
## now (the bounds check lives in the x86_64 index lowering; other backends keep the raw read).
main := fn() -> u64 {
  a := [10, 20, 30]
  i : u64 = 5
  return a[i]
}
