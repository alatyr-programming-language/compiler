## Issue #363 / Stdlib §3.6 — an external package reaches the public CharIter protocol.
## §3.6 lists `chars(in self) -> CharIter`; the appendix intro shows every operation in UFCS form
## (`x.len()` == `len(x)`), which Grammar §3.4 fixes as `a.f(args)` == `f(a, args)`, and Stdlib §1
## injects the base prelude unqualified. All three spellings are exercised below.
##
## Failure-first on parent 7774f91 (default build path, no ALATYR_OSPLIT): the qualified
## `base::str::chars(s)` is rejected with `check: invalid` because `chars` is not pub. The bare and
## UFCS spellings resolve through the unqualified base injection and already compiled on the parent,
## so they are conformance coverage of the specified spelling, not the red measurement.
##
## `for c in chars(s)` / `for c in s.chars()` ARE exercised now (#363 acceptance criterion 1, which
## #402 blocked): until #402 the loop compiled and walked the BYTE length, yielding garbage code
## points. Control Flow §6 binds `for` to the Stdlib appendix §2.4 iterator protocol, and §2.4 makes
## a type an iterator when it provides `next(in out self) -> Opt`; `test/iter_for_chars.al` owns the
## single-file measurement, and these two rows prove the loop reaches the protocol from an EXTERNAL
## package through the published surface. Representation and decoding are unchanged.

main := fn() -> u64 {
  s := "Aé€😀"

  ## the qualified §3.6 path — the surface the parent rejected
  mut cursor : CharIter = base::str::chars(s)
  copy := iter(cursor)
  if copy.pos != 0 or copy.len != s.len { return 1 }
  c0 := unwrap(char, next(cursor))
  c1 := unwrap(char, next(cursor))
  c2 := unwrap(char, next(cursor))
  c3 := unwrap(char, next(cursor))
  if u32(c0) != 65 or u32(c1) != 233 or u32(c2) != 8364 or u32(c3) != 128512 { return 2 }
  if cursor.pos != s.len { return 3 }

  ## the UFCS spelling the appendix writes — must decode the same four code points
  mut u := s.chars()
  u0 := unwrap(char, next(u))
  u1 := unwrap(char, next(u))
  u2 := unwrap(char, next(u))
  u3 := unwrap(char, next(u))
  if u32(u0) != 65 or u32(u1) != 233 or u32(u2) != 8364 or u32(u3) != 128512 { return 4 }
  if u.pos != s.len { return 5 }

  ## the bare prelude spelling (Stdlib §1)
  mut b := chars(s)
  b0 := unwrap(char, next(b))
  b1 := unwrap(char, next(b))
  if u32(b0) != 65 or u32(b1) != 233 { return 6 }
  if b.pos != 3 { return 7 }

  ## #363 criterion 1 — the `for` spelling, from outside `lib/base/str.al`, over the four code
  ## points of a string that mixes 1-, 2-, 3- and 4-byte encodings. Each index is checked on its own
  ## and every rejection code is distinct, so no total can alias a pass.
  mut i : u64 = 0
  for c in chars(s) {
    if i == 0 and u32(c) != 65 { return 8 }
    if i == 1 and u32(c) != 233 { return 9 }
    if i == 2 and u32(c) != 8364 { return 10 }
    if i == 3 and u32(c) != 128512 { return 11 }
    i = i + 1
  }
  if i != 4 { return 12 }

  mut j : u64 = 0
  for c in s.chars() {
    if j == 0 and u32(c) != 65 { return 13 }
    if j == 3 and u32(c) != 128512 { return 14 }
    j = j + 1
  }
  if j != 4 { return 15 }

  42
}
