## e2e — the register-allocated (default `ALATYR_RA=1`) IR path for a scalar RANGE `for i in lo..hi`.
## `addup` is a scalar-LEAF range-for fn (native-scalar param `n` as the loop's `hi` bound, a `u64`
## return, a loop-carried index + accumulator) → it takes the regalloc IR path: the index `i` and the
## accumulator `s` are register-resident, and the loop lowers to `mov i,lo; cmp; jge done; body; i+=1;
## jmp`. The exit code must be the SAME whether built default (regalloc) or `ALATYR_RA=0` (text
## stack-machine). sum 0..9 = 36; +6 = 42.
addup := fn(n : u64) -> u64 {
  mut s : u64 = 0
  for i in 0..n { s = s + i }
  s
}
main := fn() -> u64 {
  a := addup(9)      ## 0+1+...+8 = 36
  a + 6              ## 42
}
