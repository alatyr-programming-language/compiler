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
   *Landed as built (1c):* the hook is `ir::select_input` in each `emit_*_program` loop. A selector
   may refuse a function it cannot select and leave it to the legacy emitter: wasm refuses a member of
   a driver-disambiguated overload set, and all three refuse an `addr @g` of a global that has no
   one-word scalar cell, more than 8 parameters, or an op outside slice 1. The wasm `& 255` exit byte
   was already on `main` (`$proc_exit`, #683), so 1c moves no row for it. Twin traps carry
   `<kind> <file>:<line>:<col>`. The builder also folds literal-only `+ - *` exactly (Types §2.3)
   instead of typing each literal at the context's type.
4. **1d, `scripts/ir_diff.sh` and the x86 dev selector.** Reporting only. It proves the builder means
   what the reference lowering means before the twins' rows are trusted. It may land before 1c and
   then gates it.
   *Landed as built (1d):* the verb is `alatyr x86-ir`, a prefix to the default surface:
   `x86-ir <file>` is the GAS dump and `x86-ir -o <exe> <file>` the build. The verb sets
   `lower::X86_IR_SELECT` and drops itself from argv, so the front half, peephole and link are the
   default path's own. Under it sema records its side table over the x86 tree (`ir::sty_enable`), and
   `emit_program`'s declaration loop hands each function to `x86_isel_try` (`src/lower/isel.al`,
   prefixed `sx_`/`x86_` for #871). The selector uses frame slots and the legacy convention (`%rdi`..`%r9`,
   `%rax`, the mangled label, caller-saved scratch only), and traps with `ud2`. It refuses more than six
   parameters or arguments, a `_start`, and a function or callee whose label the legacy emitter spells
   specially (overload suffix, `@abi(c)`, `@abi(naked)`, extern). `scripts/ir_diff.sh` builds every
   corpus program with an IR-selected function both ways and compares phase, exit and stdout. It is a
   reporting stage of `scripts/full.sh`. At landing: 313 programs, 461 selected functions, 310 agree.
   The 3 that disagree are legacy x86 wrong values the IR answers per the spec: #872 (`conv_narrow`,
   `int_narrow_conv`, Types §4.2) and #875 (`lower_bugA_neg_operand`, Types §3.2 / Concurrency §6.1).
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
  I need a decision. *Decided by D6 (#786): no shape-based fallback, so this proposal is withdrawn;
  the residue it was for is §7's question.*
- **Q3: is slice 0b in scope?** §1 does the one piece of 0b slice 1 needs: sema over the emitted tree.
  The rest of 0b (`when` folding for the real target, the shared mono worklist, package roots) stays
  with whoever owns 0b.
- **D1** (unchecked division) is still open. Slice 1 keeps each target's current `hw` behaviour and
  predicts no row change for the four `unchecked_*div*` paths.

## 7. Owner question for 1e (decided: A): a generic body's node has one record, its instances have several types

**The residue.** After prerequisite (c) (#903) the 1e probe — every operand at x86's legacy
signedness decisions, self-build plus every corpus program through x86_64 — leaves 0 untyped lines in
`src/` and 109 in corpus + `lib/`. 43 of them are one structural class: the operand's type is the
**instance's** — a value of a type parameter (`a < b` over `T`, `deref(p)` of a `ptr(K)`), a pack
element, `v.(f)` in a `comptime for`. Sema checks a generic body once, with `T` unbound, and records
`VcUnknown` there (docs/ir.md §3.8 item 8). The emitter does not clone the body: `lower` re-walks the
one tree per instance with the binding in `LCtx` (`gp_s/gp_l … it3_s/it3_l`, up to three type
parameters; mono's instance identity is `Inst { gi, ts/tl, ts2/tl2, ts3/tl3 }`, `src/lower.al`). One
node, several instances, several signednesses: no per-node record can hold the answer, and 1e may not
fall back to the shape answer (D6; §6 Q2 is withdrawn by it).

**What the spec says.** Comptime §3.2/§3.4: a generic is monomorphized per comptime-argument set, and
the instances are what run. Comptime §4.3 and §9.3: Alatyr "does not fully type-check generic bodies
against constraints in the abstract"; a type error in the body "surfaces at instantiation", and a
`when`-guarded generic "is checked per satisfying instantiation". So per-instance typing is not only
what 1e's records need: it is the spec's own checking model, and today's checker (one generic pass,
`T` unknown) under-checks — a body that mixes `T` with `usize` is accepted for `T = i64` (docs/ir.md
§3.8 item 9, "Scope"). docs/ir.md §3.8 item 1 and D6: the type of every expression is decided **once,
by sema**, and recorded keyed by the node; nothing defaults it.

**Options.**

| | what changes | pros | cons | cost | x86 GAS / seed |
|---|---|---|---|---|---|
| **A. Records keyed by (node, instance)** | Sema receives mono's instance list (mono's collection walk is a pre-pass that only reads the AST, so it can run before sema) and checks each generic body once more per instance, with the type parameters bound to the instance's written arguments, recording under `key(node) ⊕ instance id`. The generic pass stays. Consumers (x86 legacy queries, IR builder, census) ask with the instance id `lower` already carries in `LCtx`. | Per-instance verdicts as Comptime §9.3 asks (the `T`-vs-`usize` mix above becomes a located error at instantiation). Every record has one meaning. No AST copies. The table and its node keys stay; only generic bodies get a second key component. | Two key shapes in one table; every consumer must pass the instance id (forgetting it reads the generic pass's `VcUnknown`, which is loud in the census, not silent). Sema walks each instance body: cost grows with instances (the self-build has few; the corpus's `lib/` generics many). Mono runs earlier than today. | Medium: sema instance loop + key scheme + an `LCtx` field read in x86 queries and the IR builder. | None by itself. 1e's own promotion covers the x86 answers that move. |
| **B. Mono clones each generic body per instance, before sema** | The front half substitutes each instance's type arguments into a copy of the body (a new AST per instance), and sema checks the copies as ordinary code. Emitters walk the clones; the `LCtx` binding (`gp_s … it3_l`) and the twins' private mono retire (slice 6). | One key shape (the node); every consumer, including the future IR builder, sees concrete code — the model docs/ir.md slices 0b/6 already assume ("the front half already monomorphised"). Per-instance verdicts. The x86 emitter loses its generic-binding paths. | The largest change: an AST substitution pass (every `Expr`/`Stmt` arm), memory per instance, and every emitter's generic path moves at once. Comptime `for`/pack expansion must be cloned per iteration too, or `v.(f)` stays unresolved. | Large (slice-sized). | Emission of instances should be byte-identical after `.L<N>` normalization, but label/symbol order may move; any move is a promotion with a one-sentence delta ("instances are emitted from their clones"). |
| **C. Symbolic record, substituted by the consumer** | Sema keeps recording the spelling `T` with its declaration (it does today, `TySpell`); an x86 query or the builder that meets a type-parameter spelling asks sema's resolver for the type the current instance binds (`LCtx`'s `gp_s/it_s` span, read through `sema_vty_name`). | Smallest: no new walk, no new key. The substitution is the one #903 already does for callee instances — of a declaration's own parameter, never a shape. Unblocks 1e's 43 lines. | No per-instance **verdict**: Comptime §9.3's checking stays a gap (to be closed by A or B later, so this work is partly thrown away). The consumer takes part in typing, which reads against D6's "sema is the single source" even if the resolver is sema's. `v.(f)` and pack elements need a per-iteration binding the consumers do not all have. | Small. | None by itself. |
| D. Shape answer for instance-dependent nodes | x86 keeps `is_signed_expr`'s shape rule where the record is `VcUnknown` | — | **Excluded by D6** ("no shape-based fallback"); listed only because §6 Q2 proposed it. | — | — |

**Recommendation, as put to the owner:** A. It is the smallest change that makes the records
mean one thing and gives the checker the per-instance model Comptime §9.3 specifies; B is the same
model with a larger blast radius and fits slice 6, where the twins' mono retires anyway; C unblocks 1e
fastest but leaves the verdict gap and reads against D6.

**Decided (owner, 2026-10-08): option A.** Records are keyed by (node, instance). Sema receives mono's
instance list (mono's collection walk runs first, as a read-only pre-pass) and checks each generic
body once more per instance, with the type parameters bound to the instance's written arguments,
recording under `key(node) ⊕ instance id`. The generic pass stays. The consumers (the x86 legacy
queries, the IR builder, the census) pass the instance id that `lower` already carries in `LCtx`.
Verdicts are per instance, as Comptime §9.3 specifies: a body that mixes `T` with `usize` becomes a
located error at its instantiation. B and C are not pursued; B's clones remain slice 6's business.
This is 1e prerequisite (e).

**What 1e can do before the answer.** The other 66 residue lines are sema gaps that do not depend on
this question: calls of values the checker types as non-functions (16), lambdas passed to a
higher-order callee (9), and the 35 assorted shapes. One more is a **spec** question, not a compiler
one: `typeinfo(T)` members (6 lines) — Comptime §5.1 names `.n`, `.fields`, `Field.offset` but gives
them no types, so sema cannot record one without the spec deciding it. The x86 switch itself (§5
item 5) cannot land with any residue, because without a fallback a node with no record has no answer.
