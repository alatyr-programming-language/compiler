## e2e: a scalar field WRITE THROUGH a POINTER FIELD of a struct — `deref(node.next).field = v`. The
## write dual of the inline linked-list / tree walk read (`deref(node.next).val`). `next` is a
## `ptr(mut Node)` field; the store must resolve the pointee through the FIELD's pointer value
## (`deref_field_ptrstruct_span`) and store at `fi*8(ptr)`. Was a silent no-op (same parser +
## `field_slot` gap as `deref(p).f = v`). Writes `b.val` through `a.next`, then sums: a.val 40 +
## b.val 2 = 42.
Node := struct { val : i64, next : ptr(mut Node) }
main := fn() -> u64 {
  mut b := Node(val = 0, next = unchecked bitcast(ptr(mut Node), 0))
  mut a := Node(val = 40, next = ptr(mut b))
  deref(a.next).val = 2
  u64(a.val + b.val)
}
