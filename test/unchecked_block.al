## e2e — the `unchecked { block }` STATEMENT verification-mode form (Grammar §130:
## `unchecked (expr | block)`). The block's statements lower with verify.checked FALSE (overflow
## guards comptime-absent); a plain in-range loop still computes correctly. 42 iterations → acc 42.
## Distinct from the pervasive EXPRESSION form `unchecked <expr>`; guards the new Stmt::Unchecked path.
main := fn() -> u64 {
  mut acc : u64 = 0
  mut i : u64 = 0
  unchecked {
    while i < 42 {
      acc = acc + 1
      i = i + 1
    }
  }
  return acc
}
