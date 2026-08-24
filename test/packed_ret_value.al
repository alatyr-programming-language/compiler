## §8 @packed struct RETURNED BY VALUE (DEFERRED, spec Types §8) — the build must FAIL LOUD.
## A struct return travels in the WORD-model return registers (field k in one whole register) and the
## caller materializes it by spilling those words at 8-byte strides; a @packed value is BYTE-precise.
## The two representations disagree and the return path applies NO packed semantics, so every caller
## shape was silently wrong: `r := mk()` then `r.b` read byte 8 of a 7-byte block (0); a PARTIAL packed
## literal returned only the words it constructed while the caller spilled one per FIELD (garbage over
## the `@offset` overlays); `@endian(big)` never swapped. `mk().b` appeared to work ONLY because the
## return and the direct register read were BOTH word-model — two errors cancelling, which stopped
## cancelling the moment the by-ref packed PARAM read was made byte-precise.
## Correct-or-trap: the decl is rejected, so no caller can observe a wrong value. build_reject
## asserts the non-zero build rc (a valid binary with a wrong result is the forbidden outcome).
Pk := @packed struct { a : u8, b : u16, c : u32 }

mk := fn() -> Pk { Pk(a = 10, b = 20, c = 12) }

main := fn() -> u64 {
  r := mk()
  u64(r.b)
}
