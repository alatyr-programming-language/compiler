- **A niche-folded `Option(ptr(T))` read through a pointer is the value it stores (#1337).**
  `v := deref(p)` and `f(deref(p))` over a `ptr(mut Option(ptr(u64)))` answered `None` for a stored
  `Some(q)`, with no diagnostic and no trap: the folded word was pushed to the by-reference `Option`
  parameter as if it were the block address, so the callee read the memory at the stored address and
  took that as the discriminant. The folding rule (Memory §4.2/§4.6 — `Option(ptr(T))` lowers
  identically to a raw pointer-width value) was applied by the FORM of the folded value — variant
  literal, folded local or parameter, call result, array element, field read — and a plain `deref(p)`
  carried no type witness of its own, so it was not among them. The witness is the pointee: a
  `deref(p)` now asks the same pointer resolver every other shape asks, and the binding, the argument
  and the assignment agree on the one folded word. `v : Option(ptr(u64)) = deref(p)`, the annotated
  binding, was already right and is unchanged. `test/issue1337_folded_deref_read.al`.
