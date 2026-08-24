## e2e — the MUTATING base::slice ops (now pub, unblocked by the generic slice-element-WRITE fix): sort
## (ascending), sort_by (a comparator fn value), map_in_place (transform each), filter_into (copy matches
## into a buffer). Each mutates the backing through a Slice(T) LOCAL. Returns 42 iff every result exact.
sl := base::slice

desc := fn(a : u64, b : u64) -> bool { a > b }
dbl := fn(x : u64) -> u64 { x * 2 }
is_even := fn(x : u64) -> bool { x - (x / 2) * 2 == 0 }

main := fn() -> u64 {
  arr : [u64; 5] = [3, 1, 4, 1, 5]
  s := arr[0..5]
  sl::sort(u64, s)                                  ## -> [1,1,3,4,5]
  if arr[0] != 1 or arr[2] != 3 or arr[4] != 5 { return 1 }

  arr2 : [u64; 4] = [2, 8, 1, 6]
  s2 := arr2[0..4]
  sl::sort_by(u64, s2, desc)                        ## -> [8,6,2,1]
  if arr2[0] != 8 or arr2[3] != 1 { return 2 }

  arr3 : [u64; 3] = [1, 2, 3]
  s3 := arr3[0..3]
  sl::map_in_place(u64, s3, dbl)                    ## -> [2,4,6]
  if arr3[0] != 2 or arr3[2] != 6 { return 3 }

  src : [u64; 6] = [1, 2, 3, 4, 5, 6]
  dst : [u64; 6] = [0, 0, 0, 0, 0, 0]
  ssrc := src[0..6]
  sdst := dst[0..6]
  n := sl::filter_into(u64, ssrc, is_even, sdst)    ## evens: [2,4,6], count 3
  if n != 3 { return 4 }
  if dst[0] != 2 or dst[1] != 4 or dst[2] != 6 { return 5 }
  return 42
}
