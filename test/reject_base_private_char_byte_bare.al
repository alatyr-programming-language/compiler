## Issue #403 — Modules §3 on the BARE spelling of a private standard-library declaration.
##
## `char_byte` (lib/base/str.al) is deliberately non-`pub`: it is the internal byte accessor the
## `CharIter` decoder uses, and #363 kept it private on purpose. This program is not `base::str` and
## is not nested inside it, so §3 lines 80-85 put it outside that declaration's visibility, and lines
## 90-92 make the `pub` chain to the root the only way anything reaches outside the package.
##
## On the parent (`8f74bed`) this file BUILDS and RUNS to 42: the `pub` test was consulted only in the
## qualified arm of `sema.al`'s resolver, so `base::str::char_byte(cur, 0)` was refused while the bare
## spelling of the same declaration resolved. Two answers for one declaration, chosen by nothing but
## how the caller wrote the name. Measured, parent, `alatyr build package.al` in an external package:
## rc=0, artifact exits 42; the same call qualified: rc=1.
##
## Lines 19-20 are the positive control INSIDE this same file: `byte_len` and `chars` are `pub` §3.6
## operations and Stdlib §1 injects the base prelude UNQUALIFIED, so the bare spelling of a PUBLISHED
## name must keep working. Only the `char_byte` call is the violation, and the diagnostic names it.
main := fn() -> u64 {
  s := "Aé€😀"
  n0 := base::str::byte_len(s)
  cur := chars(s)
  b := char_byte(cur, 0)
  if u64(b) != 65 or n0 == 0 { return 1 }
  42
}
