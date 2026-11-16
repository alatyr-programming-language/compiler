- `check` now refuses `ptr(mut …)` taken to a place whose write path is not writable — newly rejecting
  programs the specification declares invalid (Memory §4.4, §3.1/§3.3), so this is a patch. Memory
  §4.4: "an immutable place yields only `ptr(T)`", and a permission "may only be dropped, never
  gained". `ptr(mut v)` of a local declared without `mut`, of an `in` parameter, of an element of an
  `in` array parameter or of an immutable struct local were all accepted, and a write through the
  pointer then changed an immutable place; the refusal is `check: immutable binding` at the place's
  root, the direct store's own wording. `ptr(x)` of any place, and `ptr(mut x)` of a `mut` local, a
  `mut` global or an element of a `mut` array, keep compiling.
  - `dyn_over` has no carve-out (Functions §1.6, as spec#152 decided): `dyn_over(ptr(mut s))` over a
    store declared without `mut` is refused like any other such address. Write the canonical
    `dyn_over(ptr(s))`, which builds the same `dyn` value over any store; the `mut` form stays
    admissible over a `mut` store.
- `alatyr fmt` keeps the `mut` qualifier on `ptr(mut xs[1])` and any other postfix-chain operand. It
  rendered `ptr(xs[1])`, which since the entry above is a different program: the formatted text of a
  refused source compiled.
