## e2e — a MULTI-WORD struct FIELD written THROUGH a pointer from a BY-REF struct PARAM (`deref(o).i = v`
## where `v : Inner` is an aggregate param → passed BY-REF = a POINTER to the caller's Inner). Previously
## FAIL-LOUD (a by-ref param's words are behind a pointer, not contiguous in a frame slot). The fix loads
## the param pointer (emit_agg_base_addr → %rax) and reads word k THROUGH it at `k*8(%rax)` (the ascending
## pointee layout the by-ref Field read/write uses), staging into the agg-temp — an inline UNROLL emitted
## straight-line in the FieldPathAssign arm (no extracted helper). Both field words land + the neighbour
## field `t` is untouched. 30 + 9 + 3 = 42. x86-only delivery path. Neutral: src/+lib/ never do this.
Inner := struct { v : u64, w : u64 }
Outer := struct { i : Inner, t : u64 }
setit := fn(o : ptr(mut Outer), v : Inner) -> u64 { deref(o).i = v; return 0 }
main := fn() -> u64 {
  mut o := Outer(i = Inner(v = 0, w = 0), t = 3)
  setit(ptr(mut o), Inner(v = 30, w = 9))     ## by-ref struct param written through a pointer
  o.i.v + o.i.w + o.t                          ## 30 + 9 + 3 = 42 (both field words + neighbour intact)
}
