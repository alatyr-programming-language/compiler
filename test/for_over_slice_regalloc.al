## e2e — REGALLOC 6c: the ITERABLE `for x in s` over a `Slice(scalar)` PARAM in the register-allocated
## IR path. `sumslice` is scalar-leaf apart from its by-ref `Slice(u64)` param: the data-pointer and the
## length are extracted ONCE (out of the caller's {ptr,len} block the param points at) into registers, the
## hidden index is a loop-carried vreg, and each element is loaded with an indexed `movq (base,idx,8)` —
## no per-iteration frame reloads of base/len/index. The exit code must be IDENTICAL whether built default
## (regalloc + the new slice-iteration IR) or `ALATYR_RA=0` (the text stack machine). 20+3+19 = 42.
sumslice := fn(s : Slice(u64)) -> u64 {
  mut acc : u64 = 0
  unchecked { for x in s { acc = acc + x } }
  acc
}
main := fn() -> u64 {
  xs : [u64; 5] = [99, 20, 3, 19, 99]
  sumslice(xs[1..4])    ## 20 + 3 + 19 = 42
}
