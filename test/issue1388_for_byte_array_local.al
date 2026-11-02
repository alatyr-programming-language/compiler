## e2e / issue #1388 — `for x in t` over a byte-array LOCAL `t : [u8; N]` / `[i8; N]` yields its elements.
##
## A byte-array local is a packed byte run in the frame, with N in its type. The x86_64 loop read it as
## a slice local: it took the first frame word (the packed bytes themselves) for a data pointer and
## segfaulted (139). Indexing the same local (`t[i]`) was right, and so was a `[u16; N]` local.
##
## Each check owns a code from 100 up; 42 means all held. The `i8` check comes before the stored `[u8; 4]`
## loop: in the other order wasm reads -2 unsigned (#1392, a wasm defect of its own).
##
## Parent `01609666` (#1389's head, x86_64, omen): exit 139.
main := fn() -> u64 {
  t : [u8; 3] = [1, 2, 3]
  mut n : u64 = 0
  for x in t { n = n * 10 + u64(x) }
  if n != 123 { return 100 }

  ## `i8` elements are sign-extended
  ti : [i8; 3] = [1, -2, 3]
  mut m : i64 = 0
  for x in ti { m = m * 10 + i64(x) }
  if m != 83 { return 102 }

  ## a store before the loop is seen; values above 127 stay unsigned
  mut w : [u8; 4] = [9, 200, 7, 4]
  w[0] = 5
  mut sum : u64 = 0
  for x in w { sum = sum + u64(x) }
  if sum != 216 { return 101 }

  ## `continue` and `break` keep the bound
  mut k : u64 = 0
  for x in w {
    if x == 200 { continue }
    if x == 4 { break }
    k = k * 10 + u64(x)
  }
  if k != 57 { return 103 }
  42
}
## expect: run 42
