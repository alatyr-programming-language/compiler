## e2e (four-backend TEXT agreement) — the FOUR `{}`-hole shapes whose signedness the backends' own
## operand oracle cannot prove. Functions §7.1 routes every hole through the scalar rendering layer
## and gives a hole with no other type the default numeric type `i64`; Stdlib appendix §2 fixes that
## layer's integer form as "an integer in base-10 (a leading `-` for a negative two's-complement
## value, minimal digits, `0` for zero)". The spec attaches no exemption for a non-x86 target.
##
## Issue #457 (the recorded residual of #443). #443 gave aarch64/riscv64/WAT a SIGNED renderer and
## selected it with `a64_operand_signed` / `rv_operand_signed` / `wat_operand_signed` — an annotated
## `iN` param or local, an `iN(x)` conversion, a shift over one of those. Those three predicates are
## the SAME oracle `/`, `%` and `shr` route on, so widening THEM would move division and shift
## selection on three backends (measured: one extra `Expr::Index` arm turned `arr[0] / 2` from `udiv`
## into `sdiv`, `arr[0] % 3` into the signed remainder and `shr(arr[0], 1)` from `lsr` into `asr`).
## The fix is therefore a PRINT-SITE predicate layered on top of that oracle, and this fixture is what
## pins the four shapes it has to recover:
##
##   1. an UN-ANNOTATED local initialised from literal arithmetic (`inferred := 0 - 5`)
##   2. an element of an `[i64; N]` (the array's DECLARED element type)
##   3. a call whose callee's DECLARED return type is `i64`
##   4. a bare literal-arithmetic hole (`0 - 4`) — §7.1's default `i64`
##
## Each of the four is covered at `i64::MIN` as well, because the minimum has NO positive counterpart:
## a renderer that negates before converting overflows exactly there, and the magnitude of the
## minimum read as UNSIGNED is 2^63, which is the value the unfixed backends print.
##
## The last three rows are UNSIGNED controls that must NOT move: a `[u64; N]` element, a call whose
## declared return type is `u64`, and a `: u64` local at 2^64-1. They are the half of the assertion
## that proves the new predicate is layered rather than a blanket "holes are signed" default.
##
## Refs #444: like `print_hole_signed_render.al`, the assertion is the exact stdout on all four
## backends (run_x86_out + run_a64_out + run_rv64_out + run_wat_out against the SAME golden bytes),
## never the exit code — this defect leaves the exit code CORRECT, which is why the exit-code
## cross-target sweeps cannot see it.
idn := fn(v : i64) -> i64 { v }
uidn := fn(v : u64) -> u64 { v }
main := fn() -> u64 {
  inferred := 0 - 5
  inferred_min := -9223372036854775808
  arr : [i64; 3] = [0 - 6, -9223372036854775808, 7]
  uarr : [u64; 2] = [18446744073709551615, 1]
  uctl : u64 = 18446744073709551615
  print("inferred {}\n", inferred)
  print("inferred_min {}\n", inferred_min)
  print("index {}\n", arr[0])
  print("index_min {}\n", arr[1])
  print("index_pos {}\n", arr[2])
  print("call {}\n", idn(0 - 9))
  print("call_min {}\n", idn(-9223372036854775808))
  print("lit {}\n", 0 - 4)
  print("lit_min {}\n", 0 - 9223372036854775807 - 1)
  print("uindex {}\n", uarr[0])
  print("ucall {}\n", uidn(18446744073709551615))
  print("uctl {}\n", uctl)
  42
}
