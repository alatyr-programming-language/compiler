- **The shared IR builds fixed-array parameters, and copies an array field (#1626).** A function with an
  `xs : [T; N]` parameter of 8-byte elements, a call to one, and an array copy from such a parameter or
  from a struct's array field (`ys : [u64; 3] = s.arr`) are now built from the IR; before, the builder
  refused them and every backend kept a legacy emitter that answered a wrong value (x86_64 trapped or
  answered 17 where 42 was due, aarch64 224 and 5) or trapped. The array is passed as its address, the
  convention every legacy emitter uses; Functions §4.1's copy for an `in` array is not made yet (#1632),
  so a function that writes an element of its array parameter is not built from the IR and keeps its
  legacy emitter.
  A function with an array parameter is built from the IR only when every function that may call it is
  too (on every target): the aarch64 and riscv64 legacy emitters pass an array field or element by the
  value of its first element, and the twins' legacy array copies are wrong, so a legacy caller keeps the
  legacy callee and its trap (aarch64 and riscv64 had answered SIGSEGV or 1 there with the callee built).
  A function the compiler calls without its name at the call site — the index operator's `at`,
  `index_set` and `index_range`, a `@convert`, any other name the compiler synthesizes — or whose name
  is used other than in a direct call, as a function value, keeps its legacy emitter on every target.
  `alatyr ir` notes beside such a function what the rule decides.
