## §5 fmt: a TYPED top-level binding `NAME : T = v` now keeps its `: T` annotation (was demoted to
## `NAME := v`, which also dropped an `iN` signedness annotation). The parser leaves a kind-0 decl's
## type span erased (ret_tl == 0), so emit_fmt_value recovers `: T` by source-scan. An inferred `:=`
## binding stays inferred. LIMIT (40) + STEP (2) = 42.
LIMIT : u64 = 40
mut TICK : i64 = 0
STEP := 2

main := fn() -> u64 { return LIMIT + STEP }
