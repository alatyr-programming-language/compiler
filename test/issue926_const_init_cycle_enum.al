## e2e / issue #926 — a cycle through an ENUM LITERAL's payload is a cycle too, and is refused.
##
## Declarations §7.1: "a **cycle** among comptime initializers is a compile error", whatever form
## carries the reference. `A`'s initializer reads `A.k` inside the payload of `E.X(…)`, so `A`
## depends on itself exactly as `A := S(k = 1, m = A.k)` does, which was already refused.
##
## The first revision of the #926 check walked struct, array and call arguments but not an enum
## payload: this program passed `check` (rc 0), built (rc 0) and ran 7 on the parent `2188fa95` and
## on that revision alike — an ill-formed program accepted. Measured on omen, native x86_64.
##
## The refusal is located at the declaration, line 16.
E := enum { X(u64), Y }
S := struct { e : E, k : u64 }

##
A := S(e = E.X(A.k), k = 7)

main := fn() -> u64 {
  return A.k
}
## expect: reject "COMPTIME INITIALIZER CYCLE" "at line 16"
