## e2e — atomic op on ONE ELEMENT of a mutable array global. `ptr(TABLE[i])` takes the address of
## element i's `.data` cell (`leaq LABEL(%rip)` + `leaq (%base, %i, 8)`), so `atomic::fetch_add`
## updates just that slot. TABLE[1] starts 20; fetch_add(22) -> 42 (runtime index). Returns TABLE[1].
mut TABLE := [10, 20, 30]
main := fn() -> u64 {
  mut i := 1
  p := ptr(TABLE[i])
  atomic::fetch_add(p, 22, Ordering.seq_cst)
  TABLE[1]
}
