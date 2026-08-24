## e2e — whole-STRUCT element WRITE to a LOCAL struct-element array from a LITERAL (`arr[i] = Rec(…)`).
## The local-array fallback stored ONE word (`popq %rbx; movq %rbx,(%rax)`) — for a struct LITERAL RHS
## even word 0 was an address, so BOTH words were wrong (exit 0). Lower now materializes the struct in
## the agg-temp and copies `estride` words to the element base (word k at +k*8, ascending). Neutral:
## src/+lib/ index only scalar `[usize;N]` arrays + slice params (is_ref), never a local aggregate array.
Rec := struct { a : i64, b : i64 }
main := fn() -> u64 {
  mut arr : [Rec; 4] = [Rec(a = 0, b = 0), Rec(a = 0, b = 0), Rec(a = 0, b = 0), Rec(a = 0, b = 0)]
  mut i := 1
  arr[i] = Rec(a = 12, b = 30)
  u64(arr[1].a + arr[1].b)              ## 12 + 30 = 42 (both words survive; neighbours untouched)
}
