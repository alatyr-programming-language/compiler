## Types §9.1 (#602) — a WRITTEN NEGATIVE integer literal below a signed type's LOWER bound is a
## compile error through the ANNOTATION spelling: "a literal outside the target type's range is a
## compile error (I11), never a silent wrap." §9.1's positive half was closed by #564; the negative
## half survived it in BOTH spellings, because the parser did not build a `Num` for `-129` at all —
## it built `Unchecked(Bin(17, Num(0), Num(129)))`, and `ann_lit_range_bad` opens with
## `expr_is_num_lit(e) == false { return false }`, so the §9.1 test declined before it started.
##
## Measured on the parent, this program compiled clean on all four backends and RAN TO 127 — the
## silent wrap of −129 into `i8`, which is the forbidden class (I11 / #464), not a diagnostic.
## The refusal is asserted on the `-o` build path and on all three non-x86 EMIT surfaces, because
## AGENTS.md is explicit that a reject fixture does not by itself prove the emit surfaces refuse.
main := fn() -> u64 {
  n : i8 = -129
  u64(unchecked bitcast(usize, i64(n)))
}
