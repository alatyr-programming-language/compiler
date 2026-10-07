# Shared IR, slice 3 — design note and HANDOFF (aggregates, places, layout)

Status: **3a in review** (§5, #910), **3b in review** (§6). It refines `docs/ir.md` §7.2 row 3, which is the authority on scope.
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
