## e2e — `for v in TABLE` where TABLE is a MUTABLE ARRAY GLOBAL. The iterable is a module global (no
## frame slot), so it is neither the non-var nor the slot iteration path: the count comes from its
## ArrayLit and each element is read from `LABEL + i*8` (`leaq LABEL(%rip)` + indexed load). Sums the
## three scalar elements: 10 + 15 + 17 = 42.
mut TABLE := [10, 15, 17]
main := fn() -> u64 {
  mut acc := 0
  for v in TABLE { acc = acc + v }
  acc
}
