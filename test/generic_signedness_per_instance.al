## e2e — #918, docs/ir-slice-1.md §8.5: one generic body, TWO instances, each comparing with its
## OWN signedness. `lt(T,a,b)` is instantiated twice, on the same bit pattern `-1` seen two ways:
##   lt(i64, 0-1, 1)   signed   -1 < 1     TRUE   -> adds 2
##                       (unsigned it would be huge < 1, FALSE)
##   lt(u64, 1, MAX)   unsigned  1 < huge  TRUE   -> adds 40  (MAX = 2^64 - 1, the bits of -1; a
##                       written `0 - 1` at u64 borrows and traps, Concurrency §6.5, #1154)
##                       (signed it would be 1 < -1, FALSE)
## So 2 + 40 = 42 exactly when each instance keeps the signedness it was instantiated with. A
## compiler that types every `T` comparison alike answers 2 (all signed) or 40 (all unsigned).
##
## Before the fix this answered 42 on x86_64 and 2 on aarch64/riscv64/wasm: those three re-derive
## an operand's unsignedness from its SPELLING, which inside a generic body is `T` and therefore
## unprovable, so the comparison fell back to the always-signed condition. x86_64 escaped it only
## because `lower::bind_param` substitutes the instance type into the param span — an accident of one
## backend's plumbing, which is why §8.5 asks for this fixture before 1e moves the query.
lt := fn(T : type, a : T, b : T) -> bool { return a < b }
main := fn() -> u64 {
  mut acc : u64 = 0
  if lt(i64, 0 - 1, 1) { acc = acc + 2 }
  if lt(u64, 1, 18446744073709551615) { acc = acc + 40 }
  return acc
}
