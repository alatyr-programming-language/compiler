## e2e (for-over-ITERABLE over an ARRAY local — `for x in <array>` binds each element). The
## iterable `for` desugar handled a Slice VAR ({ptr,len}); an array local has its elements INLINE
## in the frame with a STATIC length (no runtime len word). The lower now recognizes a scalar-word
## array base (`ek == 5`, `eek == 0`), reads the element count from the slot (`snl`, recorded by
## bind_array_slot), and loops reading element `__i` inline at `&element0 − __i*stride*8` (the
## down-growing frame layout). Previously this SEGFAULTED (the desugar read the array's frame words
## as a bogus {ptr,len}). Sum a `[u64;3]` = 42, then a `[i64;4]`, plus a nested for-over-array, to
## confirm the index/length/back-edge are correct and nesting doesn't clobber the hidden index slot.
main := fn() -> u64 {
  a : [u64; 3] = [10, 20, 12]
  mut sum : u64 = 0
  for x in a { sum = sum + x }
  ## a longer signed array (element count 4)
  b : [i64; 4] = [1, 2, 3, 4]
  mut t : i64 = 0
  for y in b { t = t + y }
  ## nested for-over-array: each outer element paired with each inner — 3*2 iterations
  c : [u64; 2] = [1, 1]
  mut n : u64 = 0
  for x in a { for z in c { n = n + z } }
  ## a FLOAT array (eek 9): the loop var is tagged float (ek 9) so the body's float add works
  d : [f64; 3] = [1.5, 2.5, 3.0]
  mut fs : f64 = 0.0
  for w in d { fs = fs + w }
  ## sum(a)=42, t=10, n = 3 elems * (1+1) = 6, fs = 7.0 -> 42 + (t-10) + (n-6) + (u64(fs)-7) = 42
  sum + u64(t - 10) + (n - 6) + (u64(fs) - 7)
}
