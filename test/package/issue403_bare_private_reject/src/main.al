## Issue #403 — the bare spelling of a PRIVATE standard-library declaration, from a package that is
## neither `base::str` nor nested inside it. `chars` and `byte_len` are `pub` §3.6 operations and
## Stdlib §1 injects the base prelude unqualified, so both of those bare calls must keep resolving;
## `char_byte` is non-`pub` (#363 keeps it private on purpose) and must not.
main := fn() -> u64 {
  s := "Aé€😀"
  n0 := base::str::byte_len(s)
  cur := chars(s)
  b := char_byte(cur, 0)
  if u64(b) != 65 or n0 == 0 { return 1 }
  42
}
