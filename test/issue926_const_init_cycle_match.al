## e2e / issue #926 — a cycle through a `match` arm is a cycle too, and is refused.
##
## Declarations §7.1: "a **cycle** among comptime initializers is a compile error". `A`'s value is
## the arm `1 => A`, so `A` depends on itself.
##
## The first revision of the #926 check did not walk a `match`: `check` answered rc 0 and the x86_64
## build died, rc 139 SIGSEGV with no diagnostic, on the parent `2188fa95` (omen, native x86_64).
## An arm with a pattern binder is not walked, because the binder may shadow a const's name; this
## arm binds nothing, so every name in it is the enclosing module's.
##
## The refusal is located at the declaration, line 16.
B : u64 = 1

##
##
A : u64 = match B { 1 => A, _ => 2 }

main := fn() -> u64 {
  return A
}
## expect: reject "COMPTIME INITIALIZER CYCLE" "at line 16"
