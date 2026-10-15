# IR slice 4 — enums, `match`, `?`

Slice 4 of `docs/ir.md` §7.2: tags and payloads, the `match` dispatch, payload binding, range arms and
`?`. It lands in steps, each its own PR through the full gate (D8), the way slice 3 did.

| step | builds | crossings |
|---|---|---|
| **4a** | enum locals (frame objects), enum literals, `match` over an integer, `bool` or enum value (literal, range and variant arms, `_`, payload bindings), statement, tail and value position | none: an enum never leaves the function |
| 4b | enum parameters, arguments and results | the legacy conventions of each target, measured first (Q4) |
| 4c | `?` | the success variant by declaration (`docs/ir.md` §4) |

## 1. 4a — enum locals and `match` (as built)

- **Layout.** One layout for every backend: `lower_layout::enum_layout` — an 8-byte tag at byte 0, then
  the payload, one 8-byte word per component, from byte 8. The tag is the variant's discriminant from
  `lower_layout::variant_index` (explicit pins such as `B = 10` included), the same function every
  legacy emitter asks. 4a builds an enum whose every variant component is a kernel scalar and that is
  neither a union nor niche-folded (`Option(ptr(T))` is one word); a generic enum only through an
  instance span — an annotation (`o : Option(u64) = Option.Some(5)`) — since a bare `Option.Some(5)`
  names no payload type. The builder checks that `enum_layout_words` is exactly one tag word plus one
  word per component of the widest variant, so the shared layout and the IR's offsets cannot differ.
- **Literals.** `E.V(e0, …)` is a fresh object: zeroed, the tag stored, then each component in order at
  its kernel type (`ib_value_ctx`, so a literal component takes the component's type). `e := E.V(…)`
  binds the object, `e = …` builds the value in its own object and copies (#909's rule, §3.3).
- **`match`.** The scrutinee is evaluated once — an enum value in memory (its tag loaded), or an integer
  or `bool` value. The arms become a chain `if c0 { … } else { if c1 { … } else { … } }` in source
  order (Control Flow §5.3: first match wins): an integer literal arm compares for equality, a range arm
  `lo..hi` / `lo..=hi` tests both bounds at the scrutinee's signedness (#821), a variant arm compares the
  tag. `_` is the last `else`; without one the chain ends in `trap match_no_arm` (D2: unreachable for a
  well-typed program). A variant arm's bindings are `load`s of its components from the matched object,
  in the arm's own scope; a binding list names every component or none. A value `match` assigns one
  result vreg in each arm; a statement `match` in tail position returns each arm's own tail.
- **No crossing.** An enum parameter, result or argument, `ptr(e)` of an enum local, or an enum reached
  through a pointer stays `NotYet`: those paths ask `ib_struct_bound` / `ib_struct_named`, which answer
  structs only. 4b adds the crossings with each target's measured legacy convention (Q4).
- **Outside 4a** (`NotYet`): str-literal arms, comptime variant arms (`T.(v)`, `comptime for`
  templates), a value `match` whose arm is a block, a payload component that is not a kernel scalar (a
  struct, a `str`, a nested enum), a niche-folded `Option(ptr(T))`, a union, a bare generic literal.
  `ptr`-typed payload bindings are bound without their pointee, so `deref` of one stays `NotYet`.
- **Selectors.** Nothing new: the chain is `if`/`else`/`end`, `cmp`, `load`/`store`, `zero` and `trap`,
  which every selector already lowers.

### 1.1 Measured (omen, before the gate)

`corpus_manifest --check` on 4a against `main`: exactly 5 rows move, every one from a trap to the x86_64
value — `match_bool_neg` on aarch64, riscv64 (run/133 → run/42) and wasm (run/134 → run/42), and
`repr_enum` on aarch64 and riscv64 (run/133 → run/42). No x86_64 row moves. Two new fixtures,
`test/ir_match_scalar.al` and `test/ir_enum_local.al`, answer 42 on all four backends; their functions
are built from the IR (`alatyr ir`: every function `Built`).

`test/ir_agg_arg.al` and `test/ir_agg_ret.al` (slice 3d's proofs that IR-built and legacy functions
exchange structs) kept their `lg_*` functions legacy with an `Option(u64)` local, which 4a now builds —
the proofs would have silently stopped crossing to legacy code while still answering 42. They now hold a
float local instead (slice 8's construct), as `test/ir_ptr_agree.al` already did.

Few corpus rows move because almost every corpus function that matches an enum also takes or returns
one, which is 4b.
