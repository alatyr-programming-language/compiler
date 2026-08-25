## Bounded AArch64 generic-library slice: only base::slice::sort is enabled here.
## Keep this fixture independent from the still-gated sort_by/map/filter paths.
sl := base::slice

main := fn() -> u64 {
  arr : [u64; 5] = [3, 1, 4, 1, 5]
  s := arr[0..5]
  sl::sort(u64, s)
  if arr[0] != 1 or arr[2] != 3 or arr[4] != 5 { return 1 }
  42
}
