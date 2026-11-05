## #1260 — a `comptime for` range bound that subtracts past zero from a `typeinfo` member count
## unrolled ZERO times, silently. `typeinfo(P).fields` is `[Field]` and a slice's `len` is `usize`
## (Stdlib appendix), so `3 - 4` is a CHECKED unsigned subtraction that overflows: Comptime §2.6
## owes a located compile-time diagnostic and forbids materializing a wrapped value. Sema recorded
## no type for the member count, so the folder could not judge it and folded `-1` as a signed word.
## expect: reject "overflow"
P := struct { a : u64, b : u64, c : u64 }

main := fn() -> u64 {
  mut n : u64 = 0
  comptime for i in 0 .. typeinfo(P).fields.len - 4 { n = n + 1 }
  n + 40
}
