## e2e: a full linked-list WALK via a struct `ptr` field — the cursor `cur := head` (head a `ptr(Node)`
## param), `deref(cur).val`, and `cur = deref(cur).next` across a `while`. Needs a `:= <ptr-to-struct var>`
## binding to copy the ek-7 pointee type (var_ptrstruct_span) so the cursor's derefs resolve; without it
## `cur` was a scalar and every `deref(cur).val` read 0. Sums 10 + 20 + 12 = 42.
Node := struct { val : u64, next : ptr(Node) }
sum := fn(head : ptr(Node)) -> u64 {
  mut acc : u64 = 0
  mut cur := head
  while bitcast(usize, cur) != 0 {
    acc = acc + deref(cur).val
    cur = deref(cur).next
  }
  return acc
}
main := fn() -> u64 {
  mut c := Node(val = 12, next = unchecked bitcast(ptr(Node), 0))
  mut b := Node(val = 20, next = ptr(c))
  mut a := Node(val = 10, next = ptr(b))
  return sum(ptr(a))
}
