## e2e (Shape A — a MULTI-WORD aggregate as a `{}` variadic-print argument). A 3-word struct filled
## into a `{}` hole must render ALL fields, not truncate to word 0. The `{}`-template desugar routes a
## struct hole through `emit_arg` (materialize + pass its ADDRESS) + `print_one__Rec`, which renders
## by-ref via structural Display — so word 1 (`b`) and word 2 (`c`) are read, not just word 0 (`a`).
## Prints "rec { a = 11, b = 22, c = 33 }" (verified) and returns 42. Locks that the variadic gather
## does not truncate a multi-word aggregate hole.
Rec := struct { a : u64, b : u64, c : u64 }
main := fn() -> u64 {
  r : Rec = Rec(a = 11, b = 22, c = 33)
  std::fmt::print("rec {}\n", r)
  42
}
