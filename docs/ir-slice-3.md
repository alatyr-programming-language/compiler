# Shared IR, slice 3 — design note and HANDOFF (aggregates, places, layout)

Status: **3a landed** (§5, #910), **3b landed** (§6, #921), **3c landed in part** (§7: first tier #925,
fixed arrays #941; `str`/slices as two-word aggregates remain), **3d landed** (§8: #945 aggregate arguments, #947 aggregate
results), **3w** (§9: wasm frame objects and memory), **3e in review** (§10: packed/offset/endian locals). It refines `docs/ir.md` §7.2 row 3, which is the authority on scope.
§0–§2 are the plan written at the end of the slice-2 lane, §3 what that lane measured, §4 the open
questions, §5 onwards each PR as built.

## 0. What slice 3 must make true

- **Frame objects** (`docs/ir.md` §3.3): an aggregate local, an address-taken scalar and every aggregate
  temporary is its own `$k` (one object per temporary, never a shared pool) — this is what closes #769
  structurally on the twins. Verifier V6 holds every access inside its object.
- **Places**: field, index and `deref` places as `addr` + `load`/`store` at layout offsets; `copy` /
  `zero` for whole aggregates; `bound` before an index in a checked scope.
- **Typed loads** carry the field's / element's declared kernel type, so a signed field divides signed
  (#765) and an unsigned element orders unsigned (#707).
- **Layout from `lower_layout` only**, once, at build time: `@endian` (#709, `bswap`), `@offset` (#710),
  `@packed`, `@repr`; `size(T)` / `align(T)` are `const` (#713).
- **The aggregate call convention** deferred from slice 2 (`docs/ir-slice-2.md` §1): an aggregate argument
  by the address of a caller-owned copy, an aggregate result through a hidden first `ptr` (sret).
- **Statement barriers begin** (owner decision D7) — only after the function-level PRs below have landed.

## 1. The PRs (each gated alone, D8; predictions before each gate, §7.1 rule 4)

1. **3a — local structs.** Struct literal into a frame object, field read/write of a local struct, whole
   assign (`copy`), `size(T)`/`align(T)`. Selectors: `addr $k`, `load`/`store` at an offset on each twin
   (wasm: the shadow stack of `docs/ir.md` §6 — frame objects in linear memory, popped on return), `copy`,
   `zero`. Aggregate parameters/results stay `NotYet(signature)`, and an aggregate never crosses a call,
   so the IR's layout choice is internal to one function. Closes #765 (field signedness) and #713 for the
   functions it builds; Refs #769.
2. **3b — pointers as places.** `deref(p)`, `deref(p).f`, `ptr(x)` of a local (the local becomes a frame
   object), stores through a pointer; pointer arithmetic as `gep`. Here memory written by the IR is read
   by legacy code and back, so the offsets MUST equal what the twin's legacy emitter uses (§3.2).
3. **3c — arrays, index, bounds, slices/`str` as two-word aggregates.** Closes #707; `bound` traps.
4. **3d — the aggregate call convention.** By-address arguments and sret on the three twins, with the
   legacy peers' existing conventions adopted per class (`docs/ir.md` §3.7). Closes #769 (distinct
   temporaries); #771/#772 are already closed on x86 — check them as regressions only.
5. **3e — layout attributes.** `@endian(big)` (`bswap` at the field's width), `@offset`, `@packed`, `@repr`
   widths. Closes #709, #710; WRONG rows `endian_struct`, `endian_offset_struct`, `packed_attr_param`,
   `fmt_agg_body_comment`. #869 (wasm global struct with an `Option(ptr)` field) belongs here or to 3b.
6. **3f — statement barriers** (D7): only if the census after 3a–3e shows functions stalled on one legacy
   statement. Needs each twin's legacy frame-slot map; measure before designing.

## 2. Expected rows (from `docs/ir.md` §7.2 row 3)

aggregate places ~512 TRAP rows, `size(T)` 81, WRONG 19 rows (the seven paths above plus
`signedness_global_array`, `signedness_struct_field_array`, `slice_field_compare`), CRASH
`agg_arr_elem_arg`, `sret_discard_statement`. Most of these programs are LIBRARY-heavy (`alloc::vec`,
`std::fmt`): they move only when the library functions they call are buildable too, so expect the rows to
move late (3c/3d), and predict per PR by measuring, never by family.

## 3. Handoff: what the slice-2 lane measured (do not re-derive)

1. **Environment.** omen worktree `~/alatyr/ir2a` (branch push/ir2a = 2a), helper scripts in
   `~/alatyr/ir2/`: `build.sh <wt>` (seed build), `twin.sh <cc> <out> <backend> <paths…>` (emit →
   assemble → link → run per path, phase + exit + first error), `sites.sh <cc> <paths…>` (which aarch64
   `brk` comment fired: each `brk` rewritten to `exit(k)`). Base census: `~/alatyr/ir2-base-census.out`;
   2a census: `~/alatyr/ir2/2a-census.out`; 2a fresh manifest: `~/alatyr/ir2/2a.manifest`. A full gate
   takes ~45 min there now (other lanes share the box); never reset a worktree while its gate runs.
2. **Struct layout is TIERED, not one model.** `lower_layout::layout_kind`: PACKED (`@packed`), BYTE
   (§6.1 byte-precise, gated on a direct `[u8; N]` field) and WORD (one machine word per field, the
   historical model). `lower_layout::field_byte_place` is the one "where does this field start" answer
   across the tiers. The twins' legacy emitters do NOT call it: they use `field_word_offset` (aarch64 26
   sites, riscv64 24, wasm 20) and `layout_field_offset_bytes` (16/15/12). So for 3b/3d, where IR-written
   memory meets legacy code, the IR must use exactly the tier answer the twin's legacy uses for that
   type, or refuse the function — prove agreement per tier with a fixture that writes in IR and reads in
   legacy (and the reverse) before relying on it. 3a is safe from this (no aggregate crosses a call).
3. **Front half.** The twins run `driver::d_compile_file_multi`: sema's RECORD run over the emitted tree,
   then `d_resolve_and_prune` (reachability, duplicate bare labels → drop the injected lib). Since 2a the
   `when` guards fold for the real target before the prune, a qualified module value (`m::NAME`, parsed as
   its tail span) is rewritten to its declaration's name span when its bare name is unique, and a bare
   call to the caller module's own syscall declaration likewise. The builder resolves by span identity
   first (`ib_decl_named_at`).
4. **Sema records lose aggregate identity.** A recorded `VTy` is `VcAgg` with no type name, and
   `check_expr`'s `Result(Ty, CheckErr)` carrier keeps only the tag (`src/sema.al` comments at 2641, 6901,
   12588). The builder therefore cannot learn a struct-typed expression's TYPE from the side table; for
   3a take it from the declaration the expression names (a binding's annotation, a struct literal's name,
   a field's declared type) and treat any other aggregate as `NotYet`. Making the carrier keep the name is
   the same work Q3 of `docs/ir-slice-2.md` needs.
5. **wasm** keeps today's behaviour for syscalls/externs (D3/D4 spec-silent). A wasm frame object needs
   the shadow stack; until it exists, refuse aggregates on wasm in the selector (a selector refusal falls
   back per function) rather than reuse the legacy bump allocator.

## 4. Open questions

- Q3 of `docs/ir-slice-2.md` (overload resolution / sema type names) also gates aggregate-discriminated
  calls here.
- **Q4 (3b/3d).** When the IR's layout for a type disagrees with the twin's legacy layout, which one wins
  during the migration? Proposal: the legacy one for every type that crosses to legacy code (§3.7's
  "adopt the target's existing convention"), and `lower_layout::field_byte_place` only when both ends are
  IR-built — never two layouts for one type inside one program.

Q4 is settled by `docs/ir.md` §3.7 and rule 7.1.1 (owner, 2026-10-07): the proposal above, with
agreement proved per tier by a fixture that writes in IR and reads in legacy code and the reverse, and
a function refused (`NotYet`) where it cannot be proved. Q3 is settled as option (a) by D6 and is the
sema lane's; until it lands, an aggregate expression's type comes from the declaration it names.

## 5. 3a — local structs (as built)

Stacked on #901 (slice 2a) **and #903** (sema records each value's type spelling): the field reads
and the literals beside them that 3a builds are typed by #903's records; without them they are sema
gaps and fall back.

- **Builder** (`src/ir/build.al`, "aggregates"): a binding sema records as an aggregate is a struct
  local when its type — the annotation, else the struct the initializer names (a literal's name, a
  struct local) — is a struct 3a lays out: WORD or BYTE tier (`lower_layout::layout_kind`), every field
  a kernel scalar, no `@packed`/`@align`/`@offset`/`@endian` (3e). Its frame object is sized by
  `layout_type_size_bytes` and aligned as `align(T)` answers; a field's place is
  `lower_layout::field_byte_place` (a `ByteOff`). A struct literal is built into a fresh object (zeroed
  first when the layout has padding), field by field in declaration order; a field initializer that is
  a literal-only expression takes the field's declared type (Types §2.3). `s.f` is a `load` whose type
  is sema's record of the read and must equal the field's; `s.f = v` a `store`; `t := s`, `t = s` a
  `copy`; `s = S(…)` builds the literal in its own object before the copy (#909). `size(T)`/`align(T)`
  of a scalar name or of such a struct is a `const` (the values x86_64's fold answers). A type name
  resolves from the function's module (the builder publishes `set_type_ref_module` for the build, as
  x86_64's emit loop does, and restores it).
- **Selectors**: aarch64 and riscv64 place frame objects after the vreg slots (`ir::frame_place`) and
  select `addr $k`, `load`/`store` with a frame or pointer base at any offset, `copy` and `zero`
  (word loops for a multiple of 8, byte loops otherwise). **wasm** refuses a function with a frame
  object (§3.5) until the shadow stack exists. The x86_64 dev selector (`alatyr x86-ir`, D5) selects
  the same ops (`leaq`, sized `mov`, `rep movsb`/`rep stosb`), so `scripts/ir_diff.sh` compares the
  built struct functions against x86_64's legacy lowering too; x86_64's default emission is untouched.
- **Outside 3a** (`NotYet`): a struct parameter or result, a nested-struct or array field, a field
  read off anything but a struct local, a global struct, `ptr(s)`, an aggregate whose type no
  declaration names.

### 5.1 Predicted manifest transitions (measured before the gate)

Fresh manifests of the base (#901 + #903 merged) and of 3a on the gate machine, joined on (backend,
path), plus the four new fixtures:

| backend | path | before → after | why |
|---|---|---|---|
| aarch64, riscv64 | `test/size_type_arg.al` | run/133 → run/42 | `size(T)` is a `const` (#713) |
| wasm | `test/size_type_arg.al` | run/134 → run/42 | same; no frame object, so wasm selects it |
| aarch64 | `test/when_guard_struct.al` | run/133 → run/66 | `Cfg.size()` of the struct kept for aarch64 by its `when` guard: 66 is aarch64's value by the fixture's own comment |
| wasm | `test/package/module_type_shadow/src/geo/child.al` | assemble/1 → assemble/1 | `run` is selected from the IR; the program still fails to assemble on the missing `$main` |
| aarch64, riscv64 | `test/ir_struct_local.al` (new) | — → run/42 | legacy: run/133 |
| aarch64, riscv64 | `test/ir_struct_field_signed.al` (new) | — → run/42 | legacy: run/2 (#765) |
| aarch64, riscv64, wasm | `test/ir_size_align.al` (new) | — → run/42 | legacy: run/133, wasm run/134 |
| aarch64, riscv64 | `test/ir_struct_assign_self.al` (new) | — → run/21 | legacy and x86_64: 22 (#909) |

No x86_64 row moves. The new fixtures' other rows: x86_64 42 (21-fixture: 22), wasm
`ir_struct_local` run/134, `ir_struct_field_signed` run/2 (#765 on wasm), `ir_struct_assign_self`
run/0 (#909).

Few corpus rows move because a corpus function that holds a struct local almost always also calls a
library function, takes a struct parameter, or matches an enum — later slices' constructs — and the
fallback is per function (§1, item 6: 3f measures what statement barriers would add).

### 5.2 Gate (omen, `full.sh --force-sweeps`, on #901 + #903 + 3a)

Every stage green except the expected corpus-manifest mismatch, which is exactly §5.1 plus #903's own
transition (`wasm test/package/qualified_fn_alias/package.al` run/134 → run/134, stderr) and the 16
ADDED rows of the four fixtures. Fixpoint `seed == Stage1 == Stage2` (no promotion owed); e2e green;
sweeps clean (the #765 fixture is asserted with `run_x86`, because the wasm sweep walks every `run`
row and wasm still answers #765's value). `xbackend_diff --count` (fresh manifests, fixtures in both):
2619 → 2611 rows (TRAP 2276 → 2267; WRONG-VALUE 26 → 27: the two #909 rows where the twins now answer
the literal's value and x86_64 does not, and aarch64 `when_guard_struct`'s target-dependent 66, less
the two #765 rows fixed). Census, corpus functions built: 638 → 666 (`lib/` 63, `src/` 29 unchanged); verifier accepted
all 758; `ir_diff`: the #909 fixture is the one new disagreement (x86_64 22, x86-via-IR 21), beside
#875.

### 5.3 What 3a does not close

#765 stays open for wasm (no frame objects there yet) and for a struct parameter (3d); #713 for a
generic `size(T)` (slice 6) and an enum/array operand; #769 needs 3d. The twins' legacy struct paths
are still reached by every function that falls back, so none is deleted (rule 7.1.7).

## 6. 3b — pointers as places (as built)

Stacked on 3a (#910).

- **Places** (`src/ir/build.al`, "places"): a field is read or written at a base — a struct local's
  frame object, or a `ptr` vreg whose binding was declared `ptr(S)`/`ptr(mut S)` (a parameter's or an
  annotated local's type; the parser records only a parameter's `ptr` head, so the `( … )` group is
  found by bracket depth). `p.f`, `deref(p).f` read and `p.f = v`, `deref(p).f = v` write through it;
  `deref(p)` reads and `deref(p) = v` writes a scalar (sema's type of the read; the declared pointee for
  the store; the value is evaluated before the pointer, the legacy order).
- **Address-taken locals**: a local or parameter whose address `ptr(x)` the function takes
  (`ib_scan_taken`, by name, over the constructs the builder builds) lives in an 8-byte frame object;
  its reads and writes are loads and stores, and `ptr(x)` is `addr $k`. `ptr(s)` of a struct local is
  `addr $k` of its object.
- **Mutable module scalars**: a read is `addr @G` + `load` at sema's type (never folded); `G = v` stores
  the WHOLE one-word cell each target already gives a scalar global (`global_has_scalar_cell`), the
  value widened to 64 bits first. wasm selects that store as `global.set` of the `i64` global.
- **Layout agreement (Q4, rule 7.1.1).** Memory reached through a pointer may be written or read by a
  legacy-emitted function. Agreement is proved for exactly one tier: a WORD-tier struct whose every
  field is an 8-byte scalar (every model places field `i` at byte `8 i` and moves whole words), and an
  8-byte scalar pointee or address-taken local. `test/ir_ptr_agree.al` writes in the IR and reads in a
  legacy function, then the reverse, for both. aarch64's legacy emitter reads and writes `deref(p).f`;
  riscv64's has no field place through a pointer at all (a located trap), so nothing legacy-written can
  disagree there. A BYTE-tier struct through a pointer, a narrow scalar through `deref`, and a narrow
  address-taken local are `NotYet`: a narrow store would leave the upper bytes of a word a legacy
  reader loads whole, and the BYTE tier's legacy readers are not proved yet.
- **Outside 3b**: pointer arithmetic (`gep`, with arrays in 3c), a pointer whose type no declaration
  spells (an unannotated `m := ptr(x)`), `ptr(G)` of a global, nested field paths, a place reached
  through a call result.

### 6.1 Predicted manifest transitions (measured before the gate)

Fresh manifests of 3a and of 3b on the gate machine, joined on (backend, path):

| backend | path | before → after | why |
|---|---|---|---|
| aarch64, riscv64 | `test/deref_field_write.al` | run/133 → run/42 | `deref(p).f = v` through a pointer parameter |
| riscv64 | `test/accept_ptr_target.al` | run/133 → run/139 | the program dereferences a null `ptr(A)`; now the same SIGSEGV as x86_64 and aarch64 (139) |
| wasm | `test/package/visibility_pub_mut_lib/package.al`, `…/src/api.al` | assemble/1 → assemble/1 (stderr) | a function writing a `pub mut` module scalar is selected from the IR; the module still fails to assemble elsewhere |
| all | 3 new fixtures | 12 ADDED rows | `ir_ptr_place` 42 (wasm 134), `ir_ptr_agree` 42 (riscv64 133, wasm 134), `ir_global_mut` 42 |

No x86_64 row moves. Legacy values of the new fixtures (3a's compiler): `ir_ptr_place` aarch64/riscv64
133; `ir_ptr_agree` aarch64 133; `ir_global_mut` 42 everywhere (the legacy twins already agree on
whole-cell module scalars; the fixture pins the IR's store width against them).

## 7. 3c — arrays, index, bounds (as built)

### 7.1 First tier: module-global word arrays (#925)

`E[i]` over a module global whose initializer is all foldable integer words is `addr @E` + `load T`
at `i * 8`: the twins' data emitter writes such a global as a run of `.quad` cells whatever the
declared element width, so the stride is 8 by construction of the emitter, and only an 8-byte element
with a literal index inside the run is admitted (no `bound` is owed for an index proved in range).
The element's type and signedness are sema's record of the read, checked against the declared
element type. wasm keeps a global array in linear memory where its `addr @G` answers a `global.get`,
so wasm is not opened. Closed `signedness_global_array` on aarch64/riscv64.

### 7.2 Fixed arrays (this PR)

Stacked on `c67cfa8`.

- **Array locals** (`src/ir/build.al`, "fixed arrays"): `xs : [T; N] = …` with `T` a kernel scalar
  and a literal `N > 0` is a frame object of `N * stride` bytes, `stride` being
  `lower_layout::layout_elem_stride_bytes` — for a kernel scalar its own width (Types §6.4). The type
  is the annotation's; `ys := xs` takes `xs`'s (D6: the declaration names it; an unannotated
  `[1, 2, 3]` stays `NotYet`). The initializer is an array literal stored element by element, left to
  right, at the element type (its count must equal `N`: `check` accepts a shorter literal today), or
  another array local of the same layout, copied. A fill `[v; N]` is `N` references to one node (the
  parser's desugar) and is admitted only for a literal-only `v`, where evaluating it once or `N` times
  is the same. `xs = v` builds `v` in its own object first, then copies (a literal reading `xs` sees
  its old elements, as for #909). `xs.len` is the constant `N`.
- **Index places**: `xs[i]` reads and `xs[i] = v` writes. A literal index inside the array folds into
  the offset (`[$k + i * stride]`, V6-checked); any other index must be an unsigned integer (widened to
  `u64`; a signed index is refused, never reinterpreted) and is checked in a checked scope —
  `bound i, N` (`trap bounds`) before `gep (addr $k), i, stride` — and unchecked inside `unchecked`
  (Types §6.4). `xs[i] = v` evaluates the index, then the value, then checks: `a[i] = v` is
  `index_set(a, i, v)` (Types §4.5) with its arguments left to right (Functions §5.4). A literal index
  outside the array is refused (the legacy emitter decides that case today).
- **Array fields** of a 3a struct local: a field `[T; N]` with `T` an **8-byte** kernel scalar and the
  parser's `wsize == N` is admitted, at its `lower_layout::field_byte_place`, stride one word: the one
  layout every tier agrees on, so the struct's size stays x86_64's (`size(Rec)` is unchanged). The
  struct literal stores an array literal into it; `r.u[i]`, `r.u[i] = v` and `r.u.len` are places as
  above. A struct with an array field is never reached through a pointer (3b's proved tier requires
  scalar fields).
- **Literals above `i64`**: a source literal `≥ 2^63` is carried by the parser as its 64-bit pattern
  (#881); in a `u64` position it is that pattern (`ib_u64_pattern_lit`). The parser's other negative
  `Num`s are told apart by span (a folded `-N` spans its `-`, the `~x` desugar spans nothing).
- **Selectors**: `gep` and `bound` on aarch64 (`madd`; `cmp` + `b.lo` + `brk`), riscv64 (`mul`/`add`;
  `bltu` + `ebreak`) and the x86_64 dev selector (`imulq`/`addq`; `cmpq` + `jb` + `ud2`). wasm still
  refuses a function with a frame object (no shadow stack), so every array function falls back there.
- **Never crosses to legacy code (Q4)**: an array argument is an aggregate argument (3d), `ptr(xs)`
  and a slice `xs[a..b]` are refused, an array is never returned (`signature`), a nested array or an
  aggregate element is refused, `for x in xs` (the iterable `for`) is refused. So the IR's layout of an
  array local is internal to one function, as 3a's struct locals are.
- **Outside**: global arrays beyond §7.1, slices and `str` as two-word aggregates (next PR), arrays of
  structs, nested arrays, `size(xs)`/`align(xs)` of an array.

### 7.3 Predicted manifest transitions (measured before the gate)

A fresh manifest of the candidate on the gate machine, joined on (backend, path) with the committed
one — which a fresh run of the base Stage1 reproduces exactly (`match (9236 rows)`):

| backend | path | before → after | why |
|---|---|---|---|
| aarch64, riscv64 | `test/signedness_struct_field_array.al` | run/1 → run/42 | `r.u[0] < r.u[1]` over `[u64; 2]` compares unsigned (#707, field half) |
| aarch64, riscv64 | `test/array_lit_single_elem.al` | run/133 → run/42 | a `[u64; 1]` field built from its literal |
| aarch64, riscv64 | `test/signedness_ptr_field.al` | run/133 → run/64 | `main` builds `Rec(u = u64::MAX, …)` (the literal above `i64`) |
| all four | 3 new fixtures | 12 ADDED rows | `ir_array_local` 42, `ir_array_field` 42, `ir_array_bound` 132/133/133/134 |

No x86_64 row and no wasm row moves; every moved row lands on x86_64's value. `xbackend_diff --count`
on the fresh manifest: paths 951 → 951, rows 2613 → 2607 (WRONG-VALUE 25 → 23, TRAP 2271 → 2267);
every new fixture agrees on all four backends. Census: 13 corpus functions newly built (and the
fixtures' own; §7.6 has the gate's totals), `lib/` and `src/` unchanged, the verifier refused none. Ten
of the 13 answered the same before (the legacy twin was right), which the unchanged manifest rows
confirm: `checked_index_*` ×5, `checked_struct_field_array_oob`, `compound_assign_place`,
`issue215_local_array_1d_control`, `p0_stmt_walk_index_assign`, `signedness_array_elem`.

### 7.4 Found while measuring

The IR answers the spec's value on three shapes where a legacy reference does not. They are filed and
left out of the fixtures (each would add a disagreement row the ratchet refuses):
`r.u.len` of an array field answers 0 on x86_64 (#936); `ys : [u64; 3] = xs` lands shifted by one
element on x86_64 and aliases on wasm (#937); `xs = [xs[1] + 3, …]` is built in place on x86_64 (#909; fixed in 0.2.16, `test/array_assign_self.al`).
Legacy wasm also traps on `xs.len` of a local and answers a wrong value for an array reassignment;
both close when wasm selects arrays (shadow stack).

### 7.5 What 3c does not close yet

#707 stays open for wasm (both halves) and for the global-field shapes; `slice_field_compare` (a
`Slice(u64)` field compared on wasm) needs wasm aggregates (the shadow stack), so it does not move in
3c.

## 8. 3d — the aggregate call convention (as built)

### 8.1 What each legacy emitter does (measured on main 99a4237, `test/ir_agg_arg.al`'s shapes)

| target | aggregate argument | aggregate result ≤ 2 words | aggregate result > 2 words |
|---|---|---|---|
| x86_64 | address of the caller's object in `%rdi`… (`leaq`), no copy | — (step 2) | — (step 2) |
| aarch64 | address of the caller's object in `x0`…, no copy | `x0`, `x1` | not lowered (`brk`, "unsupported field access") |
| riscv64 | address of the caller's object in `a0`…, no copy | `a0`, `a1` | not lowered (`ebreak`) |
| wasm | linear-memory address, no copy | the address of a block | — |

Every callee reads the fields through the address at the WORD tier's offsets (`[x2, #0]`, `#16`, …).
§3.7 asks for the address of a caller-OWNED COPY; passing a copy's address is compatible with every
legacy callee, and reading through the address is compatible with every legacy caller. So the IR
adopts the address convention and makes the copy on its own side.

### 8.2 Step 1 — aggregate arguments (this PR)

- **Callee.** A parameter of a struct type `ib_struct_named` lays out in the WORD tier (`ib_struct_word`,
  the tier every legacy reader shares — Q4), immutable (`pmode == 0`) and not address-taken, is a `ptr`
  parameter bound as `BdRef(v, st)`: a struct value held by reference. `s.f` is a place through `v`
  (`ib_place_name`), so a field read is a `load` at the field's place with the field's declared type,
  exactly like `deref(p).f`. Reading `s` whole (`t := s`, passing it on) copies it into a fresh frame
  object (`ib_copy_into` from the `ptr` operand). `size(s)` and an assignment to `s` refuse.
- **Caller.** A struct argument is built into (a literal's own fresh object) or copied into a fresh frame
  object, and `addr $k` is passed: the callee never sees memory the caller goes on to change.
- **wasm** keeps refusing a function with a frame object (no shadow stack), so its callers stay legacy;
  a wasm callee with a struct parameter builds only when its selector takes `ptr`-based loads.
- **Proof (Q4)**: `test/ir_agg_arg.al` — IR-built `main`/`take`/`pass` call legacy `lg_take`/`lg_call` (an
  `Option` local keeps them legacy) and back; 42 on all four backends and through `x86-ir`; the register
  twins trapped (133) on the parent.

### 8.3 Predicted manifest transitions (measured before the gate)

23 pairs: the fixture's 4 ADDED rows (42 on every backend), and 19 DETAIL-CHANGED rows that keep their
phase and failure (`assemble/1`, `link/1`): an operator/overload program whose operator label the
assembler refuses (#475, slice 2b) and two FFI programs with an unresolved extern — a struct-parameter
function earlier in the file is now IR-emitted with a different size, so the error's line number or
`.text` offset moves. No row changes phase or exit; no x86_64 row moves. Census and `ir_diff` numbers
are in the PR.

### 8.4 Step 2 — aggregate results (as built)

Measured: x86_64 returns a struct's words in `%rax`, `%rdx` (and `%rcx` for a third); aarch64 and
riscv64 in `x0/x1`, `a0/a1`, and do not lower a larger struct result at all. The common convention is
one or two words in two result registers, so step 2 builds exactly that:

- **IR**: a function's result may be an aggregate of `ret_words` (1 or 2) words — `ret_ty` is `ptr` and
  `ret` carries the value's ADDRESS (`-> agg 16`). A `call` with an aggregate result receives it in a
  frame object (`$k = call …`, `set_dst_frame`). The verifier's `ret` rule is unchanged (a `ptr`).
- **Builder**: `ib_agg_ret_words` admits a WORD-tier struct of one or two words; `return`, a tail value
  and a body's trailing value go through `ib_ret_expr` (the value built or copied into a fresh frame
  object, its address returned). A call's aggregate result is `CoAgg(frame)`, used by `p := mk()`,
  `mk().f` (a place in the receiving object) and `take(mk())`; in a scalar value position it refuses.
- **Selectors**: at `ret`, aarch64/riscv64/x86-ir load the words through the address into the result
  registers; after a `call` they store the result registers into the receiving object. wasm refuses a
  function with an aggregate result (its legacy emitter returns a block's address).
- **Proof (Q4)**: `test/ir_agg_ret.al`, IR ↔ legacy in both directions, 42 on all four backends; the
  `ig_aggret` golden pins `mk(a).y` (the legacy wasm emitter cannot lower a field straight off a call,
  so a running fixture of it would add a wasm trap row).

### 8.5 What 3d does not cover yet

A struct result of three or more words (needs a convention: sret, or x86's register run), a struct
parameter that is address-taken, `in out` or assigned, a non-WORD tier (BYTE/PACKED) struct crossing a
call, and every aggregate call on wasm (shadow stack). Arrays and `str` as arguments follow with 3c's
two-word aggregates.

## 9. 3w — wasm frame objects and linear memory (as built)

`docs/ir.md` §6 puts wasm's frame objects on a shadow stack in linear memory. Before 3w the wasm selector
refused every function with a frame object and modelled memory only for module scalars (wasm globals),
so none of slices 3a–3d reached wasm.

- **Frame.** Objects are laid out from `fp`, a local holding the module's `$__sp` at entry — the legacy
  emitter's bump pointer, declared unconditionally after the aggregate globals — each at its alignment,
  and `$__sp` moves past the frame. **Not popped on return** in this step: the legacy emitter
  bump-allocates the same way and never reclaims, and a legacy callee may hand back a pointer into
  memory it bumped above the frame, so reclaiming needs a rule of its own (escape of a frame address
  and of a callee's block). Memory therefore grows per call exactly as legacy wasm's does.
- **Memory ops.** `addr $k` is `fp + offset`; `load`/`store` at any address other than a module scalar's
  are `i64.load*`/`i64.store*` of the type's width (a narrow load extended by the spelled signedness);
  `gep`, `bound`, and `copy`/`zero` unrolled by words. An address `addr @g` gave names a wasm global and
  has no memory address, so it never reaches linear-memory code.
- **Calls.** An aggregate argument is the address of the caller's copy (3d) — the legacy wasm
  convention for a struct argument. A call whose aggregate result lands in a frame object refuses on
  wasm (legacy returns a block's address; the convention is a later step): measured, dropping the
  receiving object read zeros on `test/ir_agg_ret.al` before the refusal.
- **Found while measuring:** `test/p0_void_tail_call_side_effect.al` went from a legacy trap (134) to a
  wrong value (1): with `main` IR-built, the legacy wasm `forward` turned out to have an EMPTY body — it
  drops a void call that ends a function body (#946). The builder now builds such a tail as a statement
  (all targets), so `forward` is IR-built and the row answers 42; #946 stays open for the legacy
  emitter.

### 9.1 Predicted manifest transitions (measured before the gate)

All on wasm, every one to the x86_64 value except `ir_struct_assign_self` (#909: x86_64 builds the
literal in place and answers 22; the IR — on all three twins now — answers the literal's value, 21):

| path | before → after |
|---|---|
| `ir_struct_local`, `ir_ptr_place`, `deref_field_write`, `p0_parser_if_deref_store`, `p0_void_tail_call_side_effect`, `fmt_elseif_chain_stmt`, `array_lit_single_elem` | run/134 → run/42 |
| `signedness_struct_field_array` | run/1 → run/42 (#707) |
| `ir_struct_field_signed` | run/2 → run/42 (#765) |
| `signedness_ptr_field` | run/134 → run/64 |
| `ir_struct_assign_self` | run/0 → run/21 |

plus 5 DETAIL-CHANGED rows that keep their phase and failure (`assemble/1`: overload labels, #475, and a
package that still misses `$main`) and 1 OUTPUT-CHANGED (`ir_ptr_agree`: still the same trap, at a
different instruction). No x86_64, aarch64 or riscv64 row moves. Counts and census are in the PR.

## 10. 3e — layout attributes on struct locals (as built)

- **Builder.** `ib_struct_named` admits a `@packed` struct and `@offset`/`@endian` fields (a struct-level
  `@align` and a field `@align` still refuse). Every field's place is `lower_layout::field_byte_place`,
  the one answer for every tier, so an `@offset` alias reads the bytes another field writes. A packed
  struct's frame object is aligned to 1. It stays a LOCAL value: a place through a pointer and a call
  crossing still need the WORD tier (`ib_struct_word`, Q4), so `packed_attr_param` (packed parameters)
  keeps its legacy emission.
- **`@endian(big)`.** A field's `IbFld.be`: its load is followed and its store preceded by
  `bswap T` at the field's width. `bswap T` reverses the low `T`-width bytes and its result is canonical
  at `T` — the op's definition, now in the verifier's canonical-ops set (V3). Selectors: aarch64
  `rev`/`rev16`, x86-ir `bswapq`/`bswapl`/`rolw $8`, riscv64 and wasm a byte-by-byte shift sequence (no
  byte-reverse instruction in the base ISA / in wasm); then the usual canonicalization.
- **Partial literal.** A `@packed` literal may leave TRAILING `@offset` fields unwritten (aliases of bytes
  an earlier field writes): the parser emits the written fields as a declaration-order prefix and
  refuses a gap, and the object is zeroed first.
- **Closes** the WRONG-VALUE paths `endian_struct`, `endian_offset_struct` and `fmt_agg_body_comment` on
  all three twins (#709, #710's local half). Golden `ig_agg` now pins the packed struct it used as a
  refusal example.

## 11. 3w-g — wasm selects module-global word arrays

§7.1's first tier was closed on aarch64/riscv64 only: wasm's selector refused `addr @G` of anything
but a module scalar (a wasm global). The legacy wasm data emitter already lays such a global out in
linear memory as one 8-byte word per cell, at `agg_global_base` (1024 plus the aggregate globals
declared before it), so `wat.al` hands the selector a table of (declaration index, base) for every
word-array global and `addr @G` becomes `i64.const base`. The layout stays the legacy emitter's one
decision (Q4); the selector only reads it. Closes `signedness_global_array` on wasm (#707's global
half), the last twin of that path.

## 12. Where the signature gate stands, measured at `ad28b09` (the next cut's input)

`scripts/ir_census.sh` on this tree: corpus 3 328 functions, **1 215 built**, 2 097 `NotYet` (1 957
outside the subset, 140 sema gaps); `lib/` 681 / 90 built; `src/` 4 894 / 48. The largest single reason
on every set is `signature (a parameter or result that is not a kernel scalar)` — corpus **465**, `src`
**2 547**, `lib` 170 — so the next slice is the aggregate signature, §3.7's remaining tiers.

What `ib_build_fn` accepts today (`src/ir/build.al:4295` onward), and therefore what the 465 are *not*:

- a kernel-scalar param or result (`ib_type_ks`);
- an aggregate **result** of one or two words, returned in the result registers (3d, `ib_agg_ret_words`);
- an aggregate **param** passed as the address of a caller-owned copy (3d), but only when
  `ib_struct_word` holds: not packed/byte layout, **every field a kernel scalar**, and **no padding**
  (`ib_struct_padded` compares the sum of the field bytes with the layout's size); an enum param is
  accepted by `ib_st_is_enum` (4b). `pmode != 0` and an address-taken aggregate param stay refused.

So the refused mass is: padded structs, structs with an array or nested-aggregate field, levered
(`@packed`/`@offset`) structs, params with a mode (`in`/`out`/`by-ref`), results wider than two words,
pointers and `Slice(T)` across a boundary, and every generic instance (refused earlier, as `CGeneric`).

**The census cannot say which of those dominates.** A static scan of the 2 362 corpus+`lib` sources puts
1 136 non-scalar param/result slots on names the scanner cannot resolve (a type declared in another
module, or a generic instance), so it cannot separate padded from array-field from levered. The builder
could answer this exactly — it has the layout in hand at the refusal — but it has no channel today:
`src/ir/build.al` reads no environment, and `NyWhy`/`Construct` carry one `CSignature` for all of them.
**The first task of the next slice is therefore to split `CSignature` into the shapes above** (a
refusal-class change, so the golden files and `ir_census.sh`'s ranked list move with it), re-run the
census, and cut the biggest class first. Guessing the order without that split is how a slice ends up
built for 12 paths.
