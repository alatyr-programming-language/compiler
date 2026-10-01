# Shared IR, slice 1 — design note (scalar integer core + control flow)

Status: **design, before code**. Branch `lane/ir-slice-1`, stacked on `lane/ir-slice-0a-ii`
(0a part ii, itself on part iii and on part i / PR #813). It refines `docs/ir.md` §7.2 row 1. That
row is the authority on scope, and this note says how slice 1 delivers it and in what order.

## 0. What slice 1 must make true

- On aarch64, riscv64 and wasm, a function whose body uses only the scalar subset (§2) goes through
  `build → verify → isel` instead of the legacy emitter. Every other function falls back, per
  function, with a located `NotYet` (§7.1 rules 1–2).
- **Signedness and width come from sema's side table**, never from an expression's shape. This closes
  the scalar members of #764, #766 and #725 on the twins. #777 (`and`/`or` evaluating both sides)
  closes by construction.
- **x86_64's legacy `is_signed_expr`, `is_unsigned_expr` and `is_unsigned_cmp`** (`src/lower.al:15383`,
  `:15402`, `:15486`) answer from the same table. The compiler's own source has 352 #766-shape ordering
  compares (0a census), so this owes **one seed promotion**. That makes it its own PR, gated alone
  (§5).
- **`scripts/ir_diff.sh` (§7.1 rule 5).** It builds every corpus source with x86-via-IR and compares
  against the committed x86_64 manifest row. It is reporting-only, like `xbackend_diff.sh`.
- **wasm's `_start`** passes `result & 255` to `proc_exit`.

## 1. A prerequisite slice 1 cannot skip: sema must type the tree the builder reads

The side table is keyed by `Expr` node address (`ir::sty_put`/`sty_get`). Today the twin verbs never
run sema on the tree they emit. `check_file_emit` checks a **separate parse** (`src/driver.al:6331`,
written that way because `lower_layout`'s name caches aliased between the check and the pruned emit
tree). So on the twin path every lookup answers `VcAbsent`, and the builder could build nothing.

Slice 1 therefore starts with the part of slice 0b it depends on. `d_compile_file_multi` runs
`sema::check_program` with `ir::sty_enable()` over the **pruned** `ed` it is about to emit, so the
builder and the selector read the nodes sema typed. Two things to establish first, and measure:

1. The cache aliasing that forced the separate run may already be gone. `lower_layout::layout_cache_use`
   now invalidates both name caches when the `decls` vector or its count changes. I will measure the
   630 `run` fixtures on the twins with and without the shared check before relying on it.
2. The separate `check_file_emit` stays the **verdict** (it is what `check_accept`/`check_reject` gate).
   The second check over `ed` only **records types**, and its diagnostics are ignored, so no
   accept/refuse decision moves in slice 1.

If (1) still crashes, the fix is to key the two caches by the vector's identity. That is a small
`lower_layout` change, and it is in scope here because nothing else unblocks the builder.

## 2. The scalar subset the builder accepts

Built from AST plus side table, never from the source text. Anything outside the subset is
`NotYet(construct, span)`, the function falls back, and the census ranks the reasons.

| construct | IR |
|---|---|
| params and return of kernel scalar type (`u8..u64`, `i8..i64`, `usize`/`isize`, `bool`) | vreg params, `ret v` |
| `x := e`, `x : T = e`, `mut`, reassignment, shadowing | one vreg per **binding** (§3.3: shadowing never shares one) |
| `Num` | `const`, typed from the side table. A `VcLit` the context never typed is `NotYet(untyped literal)`, never a default |
| `+ - *` | `add/sub/mul`, `chk` in a checked scope, `wrap` inside `unchecked`. A narrow type gets `fit`/`ext` (V3) |
| `/ %` | `trap_if div_zero`, and `trap_if div_overflow` for signed, then `div/rem` `s/u`. Inside `unchecked`: `hw` (D1 is open, so slice 1 keeps each target's current hardware behaviour) |
| `& \| ^`, `<< >>`, `shl/shr/rotl/rotr` builtins | `and/or/xor`. Shifts are `chk` against the **type's** width |
| `== != < <= > >=` | `cmp` with `s/u` from the operands' recorded type |
| `and`, `or`, `not` | `if` regions over a `bool` vreg: short-circuit by construction (#777) |
| `uN(x)`, `iN(x)`, `bool` conversions | `fit` (checked), or `ext` inside `unchecked` |
| `if` statement and `if` expression | `if c { … } else { … }`, a value through a result vreg |
| `while`, `loop`, value `loop`, range `for` | `block L { loop T { … } }`; the range step is `add wrap proven` after the bound test |
| `break`/`continue`, labeled, with a value | `mov result, v; br L`. The depth the parser resolved picks the region |
| `return` | `ret`. A function with `defer` is `NotYet` in slice 1 |
| `unchecked { }` / `unchecked (e)` | an `unchecked` region (V10) |
| scalar module `const` / immutable global | `const` when comptime-known. Otherwise `addr @sym` + `load` (the selector resolves the symbol by the target's existing global naming) |
| direct call to a non-generic function whose params and result are kernel scalars | `call @f(args)`. The callee may be IR-built or legacy (§3) |

Not in slice 1: aggregates and places (slice 3), `match`/`?`/enums (4), brands and `@convert` (5),
generics (6), fn values (7), floats (8), syscalls/externs/`call_c` (2). Neither are statement
barriers: the fallback is per function (D7).

## 3. Calls between IR-built and legacy functions

§3.7: during the migration each selector adopts **its target's existing convention** for the classes
it supports. For slice 1's scalar class that is:

- aarch64: arguments in `x0..x7`, the result in `x0`;
- riscv64: `a0..a7` and `a0`;
- wasm: i64 params and an i64 result;
- the symbol: the legacy label (`a64_emit_fn_label`, …), so either side can call the other.

A callee with more than 8 scalar params is `NotYet` (the legacy stack-argument layouts are not
modelled). Callee symbol mangling is unified in slice 2, not here.

## 4. Selectors (`docs/ir.md` §6)

One child module per target, as §6 names them: `src/aarch64/isel.al`, `src/riscv64/isel.al`,
`src/wat/isel.al`, plus `src/lower/isel.al` for x86-via-IR (dev only).

- **Frame-slot first.** Every vreg gets an 8-byte frame slot (§6: "frame slots first, the allocator
  later"). Operands are loaded into two scratch registers, the op is done there, and the result is
  stored. It is slow and obviously correct. The x86 dev selector does the same; the allocator comes
  at the flip.
- **Canonical form is the builder's job, not the selector's** (V3). A selector writes the full
  64-bit result of each op; `ext`/`fit` are the only width instructions it emits.
- **Traps.** `udf`/`brk #0`, `ebreak` and `unreachable` carry `// trap <kind> <file>:<line>:<col>`,
  like part iii's named traps.
- **The hook.** In `emit_*_program`'s decl loop: if `ir::build(d)` answers `Built(fn)` and the
  verifier answers `VOk`, the selector emits it; otherwise the legacy `emit_*_fn`. A verifier failure
  is a **located internal error** (§5), never a silent fallback. A builder `NotYet` is a fallback.
  Selection is per target, so a function can be IR-built on one target and legacy on another only
  when a selector refuses an op. Slice 1 aims for all three twins to accept the same set.

## 5. Order of PRs (each one gated alone, D8)

1. **1a, types on the emit tree** (§1). Twin output byte-identical. Proof: manifest `0 CHANGED`, plus
   the census of how many twin-path expressions now carry a known type.
2. **1b, the builder and `alatyr ir` building for real.** Inert: no selector consumes it yet. The
   `ir` verb prints the IR of built functions; `ir --self-test` grows golden builds; the census
   counts built functions per set. Manifest unchanged.
3. **1c, the selectors, plus the wasm exit byte.** Intentional twin transitions: the slice's expected
   rows from §7.2 (`unchecked_narrow_shift_wrap`, the MISSING-TRAP and LOUD rows, the scalar-CF traps,
   value-`loop`) and #764/#766/#777 shapes. Each moved row is predicted in advance (§7.1 rule 4).
4. **1d, `scripts/ir_diff.sh` and the x86 dev selector.** Reporting only. It proves the builder means
   what the reference lowering means before the twins' rows are trusted. It may land before 1c and
   then gates it.
5. **1e, the x86 legacy signedness queries answer from the table.** It owes the seed promotion, so it
   is the integrator's act after the gate. The delta should be one sentence: "every ordering compare
   whose operands sema types unsigned now uses `setb/seta/setbe/setae`". A delta that does not fit that
   sentence is the signal to stop.

## 6. Open questions (owner / coordinator)

- **Q1: who owns `src/ir.al`'s builder entry.** `build_fn`/`report_program` live in part i's file. I
  propose the slice-1 builder as a child module (`src/ir/build.al`), with `ir.al`'s stub replaced by a
  one-line delegation **through the 0a lane** (or by me with its agreement), so I never edit its file
  unilaterally.
- **Q2: 1e when sema has no answer.** A node sema never typed (a generic instance's clone, a desugared
  node) is `VcAbsent`. The IR builder answers `NotYet`, but the x86 legacy query must still answer
  something. My proposal: the legacy shape answer stays **only** for `VcAbsent`/`VcUnknown`, and each
  such site is counted, so the residue is measured and shrinks as sema's gaps close. §3.8 says "lose
  their shape-based fallback". Deleting it outright would refuse or miscompile every untyped site, so
  I need a decision.
- **Q3: is slice 0b in scope?** §1 does the one piece of 0b slice 1 needs: sema over the emitted tree.
  The rest of 0b (`when` folding for the real target, the shared mono worklist, package roots) stays
  with whoever owns 0b.
- **D1** (unchecked division) is still open. Slice 1 keeps each target's current `hw` behaviour and
  predicts no row change for the four `unchecked_*div*` paths.
