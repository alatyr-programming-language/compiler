## e2e — the ACCEPT sibling of the `reject_comptime_*` family, and the OVER-REJECTION guard: CT-12
## says "the two's-complement wrap of `+`, `-`, `*` and unary `-` is fully DEFINED, so those evaluate
## normally and reproducibly under `unchecked`". A legitimate comptime `unchecked` wrap must still
## evaluate — and must still carry its wrapped value at run time, so the check cannot pass by
## rejecting the whole family. The compiler's own `src/`+`lib/` lean on exactly this (the FNV/iface
## hashes multiply with deliberate overflow).
##
## Also pins the BOUNDARY values that do NOT overflow, so the new judgement cannot pass by rejecting
## everything near the edge: `2^32 * 2^32 - 1` squared, `i64 MAX + 1` as a `u64`, `u32 MAX` squared
## into a `u32`'s 64-bit computation, and the `0 - N` sentinel idiom.
K : u64 = unchecked (18446744073709551615 + 3)   ## wraps to 2
M : u64 = unchecked (9223372036854775807 * 4)    ## wraps to 2^64 - 4
N : u64 = 0 - 1                                  ## the u64 MAX sentinel idiom
P : i64 = 0 - 9223372036854775807
Q : u64 = 4294967295 * 4294967295                ## 18446744065119617025 — fits u64 exactly
R : u32 = 65535 * 65535                          ## 4294836225 — fits u32 exactly
S : u64 = 9223372036854775807 + 1                ## 2^63 — fits u64, overflows i64
T : i64 = 4611686018427387903 * 2                ## i64 MAX - 1

main := fn() -> i64 {
  x : u64 = unchecked (18446744073709551615 * 3) ## a LOCAL unchecked wrap: 2^64 - 3
  if i64(K) != 2 { return 1 }
  if M != 18446744073709551612 { return 2 }
  if N != 18446744073709551615 { return 3 }
  if P != (0 - 9223372036854775807) { return 4 }
  if Q != 18446744065119617025 { return 5 }
  if u64(R) != 4294836225 { return 6 }
  if S != 9223372036854775808 { return 7 }
  if T != 9223372036854775806 { return 8 }
  if x != 18446744073709551613 { return 9 }
  return 42
}
