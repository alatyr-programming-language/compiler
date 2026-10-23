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

## 13. The `CSignature` split, as built (the next cut's input, §12's first task)

`Construct` now names the shape it met. `CSignature` remains, set at the entry of `ib_build_one`, as
the fallback: every refusal site below names its own shape, so the census's `CSignature` row is exactly
how much of the signature mass is still unclassified, and it must stay 0.

| class | the shape refused | where |
|---|---|---|
| `CSigResultWide` | an aggregate result whose word count `ib_agg_ret_words` cannot deliver (> 2 words) | `ib_build_one`, the result tier |
| `CSigParamMode` | a parameter declared with a mode (`in`/`out`/by-ref), scalar or aggregate | both param arms |
| `CSigParamTaken` | an address-taken aggregate parameter — the callee would hold the caller's memory | the aggregate param arm |
| `CSigParamLevered` | `@packed`, or the byte tier `@offset`/`@endian` put it in: byte-exact for a LOCAL value only (Q4) | `ib_struct_word_why` |
| `CSigParamNestedField` | an array or nested-aggregate field, whose place through a pointer is unproved (Q4) | `ib_struct_word_why` |
| `CSigParamPadded` | padding the literal would leave undefined, so the caller's words are not the callee's | `ib_struct_word_why` |
| `CSigParamUnresolved` | the type name resolves to no struct or enum HERE — another module, a generic instance, `Slice(T)`, `str` | `ib_agg_named` → `None` |
| `CSigSyscall` | a syscall declaration whose signature cannot be trampolined (a non-one-word scalar, a mode, a non-integer call number) | `ib_build_syscall` |

`ib_struct_word` keeps its `bool` answer and delegates to the new `ib_struct_word_why`, so no caller
moved; the three refusals it hid are now three rows. `CSigParamUnresolved` is the residual and is
labelled as such: §12's scanner could not separate it, and this slice does not guess inside it either —
if it dominates, splitting IT (cross-module declaration vs generic instance vs `Slice`) is the next
measurement, not a lowering chosen by taste.

**Reporting-only by construction, and that is checkable:** no instruction moves, and no oracle file
contains a reason string (`grep -rl "not a kernel scalar" .` matches only `docs/ir-slice-3.md` and
`docs/ir-slice-4.md`). The prediction for the gate is therefore `0 CHANGED` on the corpus check, made
before it ran.

### 13.1 Measured (omen, `scripts/ir_census.sh --reasons 14` at `fd41e10`, after the green gate)

| shape | corpus | lib/ | src/ |
|---|---|---|---|
| `CSigResultWide` | **193** | **124** | 704 |
| `CSigParamUnresolved` | 181 | 36 | **894** |
| `CSigParamMode` | 76 | 8 | 879 |
| `CSigParamNestedField` | – | – | 60 |
| `CSigParamLevered` | – | – | 9 |
| `CSigSyscall` | – | 1 | – |
| `CSignature` (unclassified) | **0** | **0** | **0** |

**The last row is the point of the slice:** the old family label appears nowhere in the census, so every
signature refusal now names a shape. Before the split this was one row of 465 on the corpus (§12); it
is now 193 + 181 + 76 = 450 plus the same split on `lib/` and `src/`.

**What it says about where to cut next, and what it kills.** On the corpus and `lib/` — the sets the
xbackend counters are made of — the dominant signature shape is `CSigResultWide`: an aggregate RESULT
wider than two words, 193 + 124 = 317 refusals. That is §3.7's wide-result tier (sret beyond the two
result registers), and it is the next cut.

It also falsifies a guess recorded in §12. There the refused mass was listed as "padded structs, structs
with an array or nested-aggregate field, levered (`@packed`/`@offset`) structs, params with a mode …",
in that order of plausibility. Measured, padded is **absent from the corpus entirely**, levered is 9 and
nested-field 60, both only in `src/` — three shapes that would have been cut for 12 paths, exactly as §12
warned. `CSigParamUnresolved` (894 in `src/`, 181 in the corpus) is now the residual to split next: it
is a name that resolves to no struct or enum HERE, and the builder knows which of cross-module, generic
instance, `Slice(T)` or `str` it met — that is the following measurement, and this slice does not guess
inside it either.

## 14. The next cut, chosen by §13.1's measurement: aggregate results wider than two words (sret)

§13.1 measured `CSigResultWide` as the dominant signature shape outside the residual: **193 corpus +
124 `lib/` = 317 refusals**. It is one line in the builder today:

```
ib_agg_ret_words := …  if nf == 0 or nf > 2 { return 0 }      # src/ir/build.al:3999
```

Two words in the result registers is a legacy-compatibility shortcut, not the design. §3.7 already says
what an aggregate result is: **a hidden first `ptr` parameter (sret) into a caller frame object**. So this
slice is not an ABI question for the owner — the design states the answer; it is the work of implementing
the tier §3.7 names and retiring the shortcut.

What the slice must do, in the order that keeps every step gated alone:

1. **Builder.** A struct result of >2 scalar words (and, later, one with a nested-aggregate field) stops
   returning 0 from `ib_agg_ret_words` and instead marks the function `ret_sret`: the IR result becomes a
   `ptr` to a caller-owned frame object, and the hidden pointer becomes parameter 0. The existing
   `ib_agg_ret_words` register tier stays for ≤2 words — it is what today's callers and callees already
   agree on, and removing it before every backend adopts sret would break the mixed-call rule (§3.7's
   "each selector adopts its target's existing convention").
2. **Callers.** An IR-built call site of such a function reserves a frame object, passes its address as
   the hidden first argument, and uses the object as the call's value. A legacy caller of an IR-built
   callee, and an IR caller of a legacy callee, must keep working: the tier boundary is the word count, so
   until a backend implements sret it must REFUSE the signature (a located `CSigResultWide`, which is what
   it does today) rather than emit a register sequence that drops words. That refusal is the safety of the
   whole slice — no partial implementation may answer quietly.
3. **Selectors, one backend per PR.** aarch64 (`x8`), riscv64, wasm — each adopts the hidden pointer and
   returns the address; x86_64 keeps its legacy emission until slice 9 (7.4), where the same tier arrives
   with the flip. Each step is its own PR through the full gate (D8), each with its rows read before the
   oracle moves.

**What it does NOT include**, and stays refused with its own named class: a result whose fields are not
all one-word kernel scalars (nested aggregate — `CSigParamNestedField`'s sibling), a levered struct
(`CSigParamLevered`), and every generic instance (`CGeneric`). Those are separate tiers with separate
proofs; folding them in here would repeat the mistake §12 warns about.

## 15. Correction to §14 — wide results are the biggest REFUSAL but not a driver of the counter

§14 is wrong about what it leverages, and the error is worth keeping visible because it is the same
mistake §12 warns about, made while claiming to have escaped it.

`CSigResultWide` is the largest **builder refusal** on corpus+`lib/`. A refused function does not trap:
it falls back to a legacy emitter, and the legacy emitters ALREADY implement sret for wide aggregate
results — `a64_ret_sret_words` and `a64_call_ret_sret_span` in `src/aarch64.al`, with the enum analogue
at `a64_ret_enum_sret_words`. So those 317 refusals produce **no TRAP row, no WRONG-VALUE row and no
ASSEMBLE row**: they are invisible to `xbackend_diff`. Closing the tier would move functions onto the IR
(criterion 2's substance, worth doing on its own) while leaving criterion 3's `paths=`/`rows=` exactly
where they are. §14's "the counters that criterion 3 drives to zero are corpus and lib/, where wide
results dominate" conflates two different measurements: the census counts refusals, `xbackend_diff`
counts observed (phase, exit) disagreements.

**Where the counter actually is** — §2.2's `--sites` map, which names the emitter comment at each fired
trap rather than guessing:

| family | paths | rows |
|---|---:|---:|
| aggregates and places (field access, index, addr-of, field assign, struct construct, deref-store, aggregate compare, bitcast) | **239** | **512** |
| `unsupported expr` catch-all (twins' value-position arm) | 209 | 370 |
| undefined/builtin callee (`movq`, `unwrap`, `map`, `sort`, `len` …) | 97 | 235 |
| `match` shapes (#577) | 72 | 174 |
| wasm `@abi(syscall)` externs | 109 | 109 |

So the next cut by the counter is **slice 3's remaining aggregate-place rows** (512) — the same slice,
but entered through places rather than through the result tier. The `unsupported expr` catch-all (370)
sits behind it and shrinks as the arms above are claimed by name, which is what slice 0's trap-comment
naming was for.

sret stays a real task — it is §3.7's stated convention and the twins' legacy sret copies are exactly the
"private copies of a shared decision" criterion 2 removes — but it is scheduled by criterion 2, not by
criterion 3, and its PR must say so rather than promise rows.

## 16. §15's table replaced by a measurement anyone can re-take

§15 corrected §14 but kept §15's own numbers from §2.2 — and §2.2's map came from a handoff whose helper
scripts lived in `~/alatyr/ir2/` on omen and are **gone** (`ls ~/alatyr/ir2/sites.sh`: no such file). A
plan resting on numbers nobody can re-take is the same fault as §14's, one level down.

The map is reproducible from the repository after all — the tool was committed, and §2.2 named a different
path for it:

```
nix develop -c bash scripts/xbackend_diff.sh --sites "$PWD/target/debug/alatyr"
```

It prints one row per fired site: `backend  path  SITE|ASSEMBLE  <the trap comment itself>  <fn>`, because
slice 0 made every trap name its reason. Re-taken on `main` = `9d04a4b` (after #977), 2264 site/assemble
rows, grouped by reason across all three non-x86 backends:

| family | rows | paths |
|---|---:|---:|
| **undefined/builtin callee** (`size`, `answer`, `sys_mmap` …) | **623** | **263** |
| addr-of place (`unsupported expr AddrOf`, `unresolved address-of place`, `unsupported addr-of`) | 246 | 116 |
| `StrLit` in value position | 201 | 82 |
| `match` shapes (#577) | 190 | 82 |
| field access | 129 | 54 |
| unresolved var | 53 | 29 |
| `StructLit` / `EnumLit` in value position | 52 / 48 | 30 / 25 |
| `comptime-if`: unfoldable condition (needs mono context) | 72 | ~49 |
| index / array-element argument | 75 | ~49 |

§15's "aggregates and places, 239 paths / 512 rows" is not what the committed tool says: split the way the
emitters actually name their traps, places are addr-of 246 + field access 129 + index/array-element 75 ≈
450 rows over ~170 paths — real, but second, and split across three separate emitter decisions rather than
one. The mass is in **calls to a callee the emitter does not know**.

**What the count does NOT tell you, and why it must not be read as a defect list.** A trap reason is not a
verdict. `when_guard.al` traps on `answer`, and `zst_and_empty_ctor.al` traps on `size`: those are test
scaffolding that calls a deliberately undefined callee, and "fixing" them would delete the thing under test.
The filter that separates a gap from scaffolding is the fixture's OWN registration in `scripts/e2e.sh`
(`run_a64 <name> <want>` says the program is expected to run and what it must answer; `build_reject_has`
says it must be refused). Any cut taken from the table above must apply that filter first, per path, and
report how many rows survived it — otherwise the number is a count of comments, not of defects.

So the next cut by this map is `undefined/builtin callee`, and its first step is not code: it is listing
the 263 paths, splitting them by what the fixture registers, and naming which callees are missing from the
emitters. That list is the deliverable of the next slice's first PR, and it is cheap to produce.

## 17. The largest family, triaged: 363 of its 623 rows are declared-run gaps

§16 said the first step of this cut is not code but splitting the paths by what each fixture registers,
and said some of them are scaffolding whose trap is the thing under test. **That last part was wrong**, and
the tool caught it: `zst_and_empty_ctor.al` is registered `run … 42` — every backend must answer 42 — so
its trap on `size` is a defect, not scaffolding. Writing the filter down as code rather than as prose is
what made the error visible; §16's examples were hand-read and hand-wrong.

The filter is now committed: `scripts/sites_triage.sh`, reporting-only, joining
`xbackend_diff.sh --sites` with `scripts/e2e.sh`'s own registration forms.

```
nix develop -c bash scripts/xbackend_diff.sh --sites "$PWD/target/debug/alatyr" > sites.txt
bash scripts/sites_triage.sh --sites sites.txt
```

Measured on `main` = `5bcb96f`, the `undefined/builtin callee` family (matched as a REGEX — x86/aarch64/
riscv64 write `undefined/builtin callee`, wasm writes `call to undefined/builtin fn X`, and a plain
substring silently drops wasm, which is how the first run of this tool lost 226 rows):

```
623 rows triaged, 263 distinct paths
   198  backend riscv64     226  backend wasm     199  backend aarch64
   363  GAP:declared-run        ← the fixture says run <name> <want>; this backend traps
   140  undeclared-here            another backend is asserted, not this one
   120  UNREGISTERED               no registration names it (packages included)
```

So the answer to "how much of criterion 3's largest family is real" is **363 rows**, not 623 and not zero.
The per-backend line is in the output on purpose: a family spread over all three twins is one task, and a
backend missing from that list means the matcher dropped it.

### What the twins are stuck on, and why the list is incomplete

The callee histogram the tool prints is **wasm-only**: wasm writes the callee's name into its trap comment,
while aarch64 and riscv64 write a fixed string with no name —

```
src/wat.al:5898      (unreachable) (; call to undefined/builtin fn <name> ;)
src/aarch64.al:5822  brk #0 // undefined/builtin callee
src/riscv64.al:5049  ebreak # undefined/builtin callee
```

So 398 of the 623 rows name no callee, and the histogram (sys_mmap 83, size 11, unwrap 7 …) describes only
the wasm third of the family. Naming the callee in the twins' comment would fix that, and it is exactly what
slice 0's trap-naming rule exists for — but it changes emitted text, which moves the corpus manifest hashes
for every affected path: an oracle regeneration, not a free change. It is therefore listed as a decision
below rather than done here.

### The first concrete gap, root-caused

`zst_and_empty_ctor.al` (registered `run … 42`; x86_64 answers 42, aarch64 and riscv64 trap 133, wasm 134):

```
fn zst_and_empty_ctor::take_marker NotYet(signature: parameter type names no struct or enum resolvable here, :23:1)
```

`take_marker := fn(z : Z)` with `Z := struct {}`. `ib_struct_named` returns `None` when a struct has no
fields (`if nf == 0 { return None }`), so a ZERO-SIZED struct is not a type the builder can name — and that
refuses every function mentioning `Z`, including `size(Z)` and `align(Z)`, which the builder otherwise folds
(`ib_bx_layout_q`, `LayoutQ.LqSize/LqAlign`). Spec §6.5 settles the layout — size 0, alignment 1, "zero-sized
types are permitted" — so the refusal is not a spec gap.

What the spec does NOT settle is how a ZST crosses a call. x86_64 today passes the **address of a scratch
stack slot** (`leaq -8(%rbp), %rax; movq %rax, %rdi`), so it consumes a register while the type occupies no
bytes. That is an implementation choice, not a spec rule, and it is the owner's to make — see #979.

## 18. §17's headline number was wrong, and why it mattered

§17 reported **363 `GAP:declared-run` rows** — "the fixture says run <name> <want>, this backend traps".
That was read out of a wrong premise in `scripts/sites_triage.sh`: it treated `run <name> <want>` as an
**all-backend** declaration. It is not. `run()` in `scripts/e2e.sh` compiles with `"$CC"`, the default
target, which is x86_64:

```
run() { # name, want
  "$CC" -o "$out" "$src" >/dev/null 2>&1 || { echo "FAIL $1: compile/link"; fail=1; return; }
```

The twins are spoken for only by `run_a64` / `run_rv64` / `run_wat` (and `*_out`, `*_trap`). Re-measured on
`main` = `d03e80f` with the premise fixed, the same 623 rows classify as:

```
623 rows triaged, 263 distinct paths
   198  backend riscv64     226  backend wasm     199  backend aarch64
    30  declared-package-build
   503  undeclared-here(x86-only)      ← nothing says what the twins must do
    90  UNREGISTERED
     0  GAP:<backend>                  ← not one twin trap contradicts a declaration
```

**Zero.** So the family's shape is not "the twins fail an expectation" — it is "**no expectation for the
twins was ever written**". That is a different task, and it is the real one: 503 sites where x86_64 has a
declared answer and the twins have no test at all. The divergence persists not because a test fails but
because nothing asserts the twins' behaviour, which is exactly what criterion 3's "unexplained" means.

The actionable move follows from the shape, not from taste: for each such program, x86_64's declared answer
is the candidate expected value for the twins; promote `run <name> <want>` to `run_a64`/`run_rv64`/`run_wat`
**only where the twin actually answers it**, and leave a `*_trap` registration where it does not. Each
promotion turns an undeclared divergence into a tested requirement; each one that is promoted without the twin
passing would be a false declaration, so promotion order is: measure per backend, then register.

Verified for four programs already, in #980: `packed_in_plain_struct` returns `u64(g.p.b)` = 20 and the
twins answer 20; `deep_field_agg_var_reject` returns 12 + 30 = 42 and they answer 42 — there the twins are
right and x86's `build_reject_has` is the stale entry.

The callee histogram §17 printed (`sys_mmap 83`, `alloc 56`, `size 35`) survives, but it now describes
`undeclared-here(x86-only)` rows, not gaps — the names came from #981's trap naming, which is what made
them visible at all.
