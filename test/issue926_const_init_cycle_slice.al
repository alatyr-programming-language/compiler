## e2e / issue #926 — a cycle through a SLICE bound is a cycle too, and is refused.
##
## Declarations §7.1: "a **cycle** among comptime initializers is a compile error". `B`'s upper
## bound is `C`, and `C` is `B.len`: neither has a value until the other has one, so there is no
## dependency order to evaluate them in.
##
## The first revision of the #926 check did not walk a slice's operands. This program passed
## `check` (rc 0), built (rc 0) and RAN 0 on the parent `2188fa95` — a value made up for a binding
## that has none. Measured on omen, native x86_64.
##
## The refusal is located at the first declaration of the cycle in source order, `B`, line 16.
A : [u64; 3] = [1, 2, 3]

##
##
B := A[0..C]
C : u64 = B.len

main := fn() -> u64 {
  return C
}
## expect: reject "COMPTIME INITIALIZER CYCLE" "at line 16"
