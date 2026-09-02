## e2e — Control Flow §6 / Stdlib appendix §2.4: `for` over an ITERATOR drives `next`, it does not
## count a slice. §2.4 makes a type an iterator when it provides `next(in out self) -> Opt`, and only
## an `iter` returning a slice `[T]` takes the built-in counted loop; `CharIter` provides `next`, so
## `for c in chars(s)` must walk CODE POINTS.
##
## Failure-first on parent f14b3d9 (x86_64, default build path): every spelling below compiled and ran
## the backing view's BYTE length — `"Aé€😀"` is 4 code points in 10 bytes, so the loop ran 10 times
## and the yielded values were `65, 152, 0, 78, 0, 0, 0, 0, 0, 0`: neither the code points nor the raw
## bytes. Measured `101` (the index-0 value mismatch, the first guard that can fire) on the parent
## and `42` here. The string deliberately mixes 1-, 2-, 3- and 4-byte encodings: on
## single-byte ASCII the byte count equals the code-point count and the defect is invisible.
##
## Each code point is checked at its own index and every rejection code is distinct and >= 100, so no
## sum or product can alias a pass (#386). `unwrap`/`next` driven explicitly is NOT re-proven here —
## `issue363_chariter_public` owns that — this fixture proves only the loop FORM.

cp_at := fn(i : u64) -> u64 {
  if i == 0 { return 65 }        ## `A`  — 1 byte
  if i == 1 { return 233 }       ## `é`  — 2 bytes
  if i == 2 { return 8364 }      ## `€`  — 3 bytes
  return 128512                  ## `😀` — 4 bytes
}

main := fn() -> u64 {
  s := "Aé€😀"

  ## the bare prelude spelling (Stdlib §1 injects the base prelude unqualified)
  mut i : u64 = 0
  for c in chars(s) {
    if i > 3 { return 100 }
    if u64(u32(c)) != cp_at(i) { return 101 + i }
    i = i + 1
  }
  if i != 4 { return 106 }

  ## the UFCS spelling the appendix writes (`x.f()` == `f(x)`, Grammar §3.4)
  mut j : u64 = 0
  for c in s.chars() {
    if j > 3 { return 107 }
    if u64(u32(c)) != cp_at(j) { return 108 + j }
    j = j + 1
  }
  if j != 4 { return 113 }

  ## a NAMED iterator place — the hand-built `CharIter` #402 measured, so the fix cannot depend on
  ## the iterable being a call
  mut cur := base::str::CharIter(ptr = s.ptr, len = s.len, pos = 0)
  mut k : u64 = 0
  for c in cur {
    if k > 3 { return 114 }
    if u64(u32(c)) != cp_at(k) { return 115 + k }
    k = k + 1
  }
  if k != 4 { return 120 }

  ## the loop drives a COPY: `next` takes `in out self`, and the appendix's `iter` "Returns a
  ## constructor copy", so the author's iterator is not advanced behind their back.
  if cur.pos != 0 { return 121 }

  ## an EMPTY string yields nothing at all (the absent branch on the first `next`)
  e := ""
  mut n : u64 = 0
  for c in chars(e) { n = n + 1 }
  if n != 0 { return 122 }

  ## a `break` out of the desugared loop still exits it, and `continue` still advances it
  mut b : u64 = 0
  for c in chars(s) {
    b = b + 1
    if b == 2 { break }
  }
  if b != 2 { return 123 }
  mut d : u64 = 0
  for c in chars(s) {
    if u64(u32(c)) == 233 { continue }
    d = d + 1
  }
  if d != 3 { return 124 }

  42
}
