# Shared IR, slice 3 — design note and HANDOFF (aggregates, places, layout)

Status: **plan, before code.** Stacked on `lane/ir-slice-2a` (PR #901). It refines `docs/ir.md` §7.2
row 3, which is the authority on scope. This note was written at the end of the slice-2 lane as the
handoff for a fresh lane: §0–§2 are the plan, §3 is what the previous lane measured and must not be
re-derived, §4 the open questions.

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
