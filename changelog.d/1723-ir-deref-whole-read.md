- **The shared IR builds `deref(p)` read whole, and names why it does not (#1723).** In value context
  `deref(p)` loads the pointee (Memory §4.3). When the pointee is an aggregate, the builder now copies it
  out of the address into a fresh value of its own, as it already did for a parameter passed by reference.
  It does this only when the operand's declaration spells the pointee type: a pointer name declared
  `ptr(T)`, a call declared `-> ptr(T)`, or `bitcast(ptr(T), x)`. The pointee must also be an enum in the
  shared layout or a struct in the WORD tier. So `v : S = deref(p)`, `match deref(q) { … }` and
  `f(deref(g()))` are built where they were refused. An enum whose variant carries a niche-folded
  `Option(ptr(T))` component is laid out too: the component is the one pointer word in its slot
  (Types §6.2), and a match binding over it is an `Option` value that can be matched again.
  Every remaining refusal names its cause instead of a bare `expr Deref`: the pointee type is not
  spelled, the builder does not lay out the pointee, the struct is not in the WORD tier, or the scalar is
  narrower than a word.
