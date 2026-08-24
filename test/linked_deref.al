## e2e: traversing a linked structure via a struct `ptr` field — `n := node.next; deref(n).field`. The
## binding `n := node.next` (where `next : ptr(Node)`) formerly fell to a SCALAR slot, so `n` carried no
## pointee type and `deref(n).val` read 0. Now `collect_slots` recognizes a `Field` RHS of `ptr(Struct)`
## type (`field_ptrstruct_span`) and binds `n` as a pointer-to-struct (ek 7), so the deref resolves the
## field through the pointer — the idiomatic linked-list / tree walk. b.val=2, a.val=40 → 42.
Node := struct { val : u64, next : ptr(Node) }
main := fn() -> u64 {
  mut b := Node(val = 2, next = unchecked bitcast(ptr(Node), 0))
  a := Node(val = 40, next = ptr(b))
  n := a.next
  return deref(n).val + a.val
}
