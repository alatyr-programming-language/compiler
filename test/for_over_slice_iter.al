## e2e — `for x in s` over a scalar-array SLICE VIEW `s := xs[lo..hi]`. The slice binds `ek==5 is_ref`
## (a runtime {ptr,len}); the for-emit formerly mis-took it for an INLINE array (is_arr) and read its
## ptr/len slots as elements against a hardcoded static count. Now a scalar/float slice VIEW reads its
## runtime len (word 1) and derefs its element pointer (word 0) BY VALUE. Sum xs[1..4] = 20+3+19 = 42.
main := fn() -> u64 {
  xs : [u64; 5] = [99, 20, 3, 19, 99]
  s := xs[1..4]
  mut sum : u64 = 0
  for x in s {
    sum = sum + x
  }
  return sum
}
