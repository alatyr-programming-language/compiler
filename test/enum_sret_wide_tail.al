## e2e / rv64 NON-X86 BREADTH — wide-enum SRET TAIL-FORWARD: `return inner()` where BOTH the outer and
## the inner fn return an enum wider than the register-return budget, so both deliver through the
## indirect result pointer. The outer fn must hand the INNER call its OWN incoming destination pointer
## (reloaded from its spill slot) rather than stage the block in a scratch and copy it — otherwise the
## inner callee is reached with no destination at all. `W.Many(...)` = disc + 10 payload = 11 words.
## `tailval` additionally exercises the TRAILING-VALUE (no explicit `return`) flavour of the same
## forward. The readers take the FIRST, a MIDDLE and the LAST payload word:
## (2 + 6 + 11) + (2 + 6 + 11) = 19 + 19 = 38.
##
## NOT yet wired into scripts/e2e.sh: riscv64 and aarch64 both answer 38, but the x86_64 backend answers
## 0 — a SILENT MISCOMPILE on BOTH tail-forward flavours (the forwarded value is dropped). Add the
## `run enum_sret_wide_tail 38` line once src/lower.al handles it.
W := enum { Many(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64), Small(u64) }

inner := fn() -> W { return W.Many(2, 3, 4, 5, 6, 7, 8, 9, 10, 11) }

outer := fn() -> W { return inner() }          ## explicit-return tail-forward

tailval := fn() -> W { inner() }               ## trailing-value tail-forward

main := fn() -> u64 {
  v := outer()
  w := tailval()
  s := match v {
    W::Many(a, b, c, d, e, f, g, h, i, j) => a + e + j   ## word1(2) + word5(6) + word10(11) = 19
    W::Small(x) => 0
  }
  t := match w {
    W::Many(a, b, c, d, e, f, g, h, i, j) => a + e + j   ## 19
    W::Small(x) => 0
  }
  s + t                                                   ## 38
}
