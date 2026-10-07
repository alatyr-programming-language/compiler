# One semantic lowering for four backends — the shared IR

Status: **design, not yet implemented.** This document changes no compiler behaviour. It records a
measurement of the four emitters as they stand at `a46b5bc`, proposes one intermediate representation
(IR) that all four consume, and lays out a migration in vertical slices that keeps every gate green and
the fixpoint intact at every step. Tracking issue: #683.

Contents: [1 Why](#1-why) · [2 Measurement](#2-measurement) · [3 The IR](#3-the-ir) ·
[3.8 Signedness as a value attribute](#38-signedness-and-width-are-attributes-of-the-value-derived-once) ·
[4 How each construct lowers](#4-how-each-construct-lowers) · [5 The verifier](#5-the-verifier) ·
[6 How the four targets consume it](#6-how-the-four-targets-consume-it) ·
[7 Migration plan](#7-migration-plan) · [8 Decisions for the owner](#8-decisions-for-the-owner) ·
[9 Method](#9-method)

---

## 1. Why

The compiler has four emitters, and each one re-implements the language's semantics from the AST:

| emitter | lines | code model | what it reads |
|---|---:|---|---|
| x86_64 — `src/lower.al` + `src/lower/*` (+ `src/regalloc.al`) | 28 840 + 12 253 + 1 171 | text stack machine, plus a register-allocated fast path for scalar leaves (`src/lower/ir.al`) | the AST and the source text; sema gives it a verdict only |
| aarch64 — `src/aarch64.al` | 9 214 | stack machine, every value in `x0` | the AST and the source text |
| riscv64 — `src/riscv64.al` | 8 235 | stack machine, every value in `a0`; ~70% of its non-comment lines are aarch64's after renaming `a64_`→`rv_` | the AST and the source text |
| wasm — `src/wat.al` | 8 373 | every value an `i64` local; aggregates bump-allocated in linear memory, never reclaimed | the AST and the source text |

All four share `src/lower_layout.al` (5 164 lines of layout, enum and scalar-name queries) and
`src/lower_ctx.al` accessors. **Nothing else is shared**: each emitter decides widths, signedness,
checked-versus-wrapping arithmetic, narrowing, short-circuit evaluation, `match` dispatch, `?`,
monomorphisation, comptime folding, call conventions and symbol names on its own.

Two facts make this structural rather than a backlog of bugs:

1. **Sema hands lowering no types.** `sema::check_program` returns a single `usize` verdict
   (`src/sema.al:54-56`, "The public checker returns only a scalar verdict"). The AST carries source spans
   and child pointers, no type slots, and there is no side table. Every emitter therefore reconstructs
   types from annotation text — x86 through `expr_type_span` / `is_signed_expr` / `is_unsigned_cmp`, the
   twins through `a64_operand_signed_dep`, `rv_operand_signed_dep`, `wat_operand_signed_dep` — and each
   reconstruction has its own "unknown" default. x86's is *signed compare, unsigned divide* (comment at
   `src/lower.al` ~17207); the twins treat an unproven operand as unsigned; wasm's `wat_binop` defaults
   `/`, `%`, `shr` and the checked guards to unsigned but comparisons to signed. The newest wrong-value
   issues are this one mechanism: #764 (signed `/`/`%` divides unsigned on all four), #765 (a signed
   struct field divides unsigned on the twins), #766 (a `u64` ordering compares signed).
2. **The twins do not run the x86 front half.** `driver::d_compile_file_multi` (`src/driver.al:5956`)
   parses, lifts lambdas, desugars `for`-in, fills default arguments and hands the raw `decls` to the
   emitter — "minus the x86-only tail (test runner, `_start` wrapper, sema, limits, lambda lifting,
   peephole)". Sema is run separately by `check_file_emit` for the verdict only, because sharing its
   `lower_layout` caches with the pruned tree crashed the backends (`src/driver.al:6201-6215`). So each twin
   also carries its own monomorphiser (`a64_inst_add`, a fixed 512-entry table, at most three type
   parameters), its own comptime folder (the source of #672, `src/aarch64.al:2638-2646`), and its own
   symbol mangling.

`scripts/xbackend_diff.sh` (#763) measures the result on the committed manifest: **958 paths / 2 656
rows** disagree with x86_64. The specification already says the fix: "the internal IR and the
**portable-core** lowering (types, functions/ABI, structured control flow, data, comptime) are shared.
The register-ISA pipeline is the v1 instance; raw constructs (registers, raw transfer, `asm`) are a
**target-capability**, absent on a structured/VM backend" (spec `90-codegen.md` §1.2, CG-4). The same
section lets a conforming compiler "use an internal IR … as a private implementation detail, provided its
observable lowering matches the rules". This document designs that IR.

---

## 2. Measurement

### 2.1 Disagreements by class (`scripts/xbackend_diff.sh --count`, manifest of 2 186 sources)

```
xbackend diff: paths=958 rows=2656 sources=2186
  class           paths   rows   aarch64 riscv64    wasm
  WRONG-VALUE        10     24         8       7       9
  MISSING-TRAP        7     14         7       7       0
  CRASH               4      5         2       3       0
  LOUD-EXIT           7     10         0       0      10
  TRAP              757   1849       572     585     692
  ASSEMBLE           84    141        29      29      83
  LINK                4    380       190     190       0
  ACCEPTS            85    233        74      78      81
```

### 2.2 TRAP rows by the feature the twin is missing

Each TRAP row was rebuilt with `--sites` (every trap instruction rewritten to `exit(k)`), which names the
emitter's own comment at the site that fired. The families below group those comments. riscv64's
`ebreak`s mostly carry no comment (566 bare sites fired), so a riscv64 row borrows the aarch64 cause for
the same path, and an aarch64 "undefined/builtin callee" borrows the wasm callee name. Totals match the
1 849 TRAP rows.

| family (site comments) | paths | rows | a64 | rv64 | wasm |
|---|---:|---:|---:|---:|---:|
| aggregates and places (`unsupported field access`, `index`, `addr-of`, `field assign`, `struct construct`, byte-tier ABI, deref-store, aggregate compare, bitcast to aggregate …) | 239 | 512 | 172 | 182 | 158 |
| `unsupported expr` catch-all — on aarch64 the arm is `StructLit \| EnumLit \| StrLit \| ArrayLit \| Try \| Slice \| Lambda \| Loop` in value position (`src/aarch64.al:5989`), on wasm `AddrOf \| Deref \| StrLit \| Lambda` (`src/wat.al:6249`) | 209 | 370 | 110 | 107 | 153 |
| undefined/builtin callee (`movq`, `unwrap`, `map`, `sort`, `forget`, `checked_add`, `bytes`, `len` …) | 97 | 235 | 87 | 88 | 60 |
| `match` shapes (#577) | 72 | 174 | 57 | 57 | 60 |
| `@abi(syscall)` externs on wasm (`sys_mmap` 108, `sys_write` 1) | 109 | 109 | – | – | 109 |
| comptime and generics (`comptime-if: unfoldable condition (needs mono context)`, `comptime-for pack`, `generic call: unresolved type-arg`, `compiles`, `dyn_over`) | 34 | 96 | 32 | 32 | 32 |
| brands, `@convert`, bitcast (`Checked(v)`, `NonZero(v)`, `T(v)`, `unsupported bitcast`) | 32 | 82 | 25 | 25 | 32 |
| `size(T)` (#713) | 27 | 81 | 27 | 27 | 27 |
| `unresolved var` | 23 | 61 | 22 | 23 | 16 |
| enums (`str enum payload`, `unknown enum variant`, `unsupported enum return value`) | 20 | 39 | 18 | 18 | 3 |
| `for`-in over an iterable | 11 | 33 | 11 | 11 | 11 |
| fn values (`local lambda direct call supports <= 8 integer scalar args`, `bare local lambda value`) | 17 | 26 | 9 | 9 | 8 |
| floats (`float module global (wasm: no init)`) | 15 | 19 | 0 | 4 | 15 |
| scalar control flow (`labeled break value is not scalar integer`) | 7 | 7 | 0 | 0 | 7 |
| other | 2 | 5 | 2 | 2 | 1 |

The non-TRAP classes, by cause:

- **LINK 380** = 242 `@abi(syscall)` rows on aarch64/riscv64 (121 paths each: `sys_mmap` 107, `sys_write`
  13, `sys_clock_gettime` 1 — the twins never emit a kind-4 declaration, so `bl sys_mmap` is left
  unresolved) + 138 package-root rows (69 `test/**/package.al` paths × 2: the twin emit verbs compile the
  manifest as if it were a program and `_start` calls a `main` that does not exist).
- **ASSEMBLE 141** = 70 wasm package-root rows (the same cause, spelled `undefined function variable
  "$main"`) + overloads and operator functions the twins do not mangle (`symbol already defined`,
  labels like `f__+:`, #475) + the `movq` intrinsic spelled as an x86 mnemonic on the twins + two
  wasm type mismatches.
- **WRONG-VALUE 24**: `@endian` / `@offset` / `@packed` ignored (#709, #710: `endian_struct`,
  `endian_offset_struct`, `packed_attr_param`, `fmt_agg_body_comment`); signedness of an array element
  (#707: `signedness_global_array`, `signedness_struct_field_array`); an unnarrowed narrow shift
  (`unchecked_narrow_shift_wrap`); wasm's `Slice(T)` field compare; wasm's comptime-match template
  (#712); `when_guard_binding` (aarch64's 100 is correct there, the fixture selects it).
- **MISSING-TRAP 14**: the narrow *checked* guard exists on x86 only (`checked_index_overflow`,
  `checked_index_bind_ovf`, `checked_narrow_shift_oob`), and four `unchecked` division shapes whose
  result is hardware-defined (§8, decision D1).
- **CRASH 5**: `agg_arr_elem_arg`, `sret_discard_statement` (#714), `comptime_enum_eq`,
  `fmt_comptime_arm_template`.
- **LOUD-EXIT 10** (wasm): an `unknown import` for a bodyless extern (3), and wasm's `_start` passing the
  whole `i64` to `proc_exit` (7) — which hides the value, and in two `@convert` cases hides a wrong one.
- **ACCEPTS 233**: mostly `reject_*` fixtures that x86 refuses **in its lowering** (232
  `codegen_reject`/`panic("selfhost…")` sites in `src/lower.al`) while the twins compile them. A located
  refusal is a semantic decision too, and it lives in one emitter.

### 2.3 Construct support today

Read from the code and cross-checked against the TRAP sites above. **S** supported, **P** partial,
**T** traps (fail-loud stub), **W** compiles and answers a wrong value, **–** not applicable.

| construct | x86_64 | aarch64 | riscv64 | wasm | notes |
|---|:-:|:-:|:-:|:-:|---|
| wrapping and checked `+ - *`, 64-bit | S | S | S | S | four implementations of the guard |
| narrow widths (`i8`…`u32`): checked guard and wrap | S | P | P | S | twins miss the narrow checked guard on some shapes (MISSING-TRAP); narrow shift result unmasked on aarch64/riscv64 |
| `/ %`: zero and `MIN / -1` | S | S | S | S | the signedness choice behind them differs (#764, #765) |
| shifts, rotates, shift-count trap | S | P | P | S | |
| comparisons, signedness | S | P | P | P | three different "unknown" defaults (#766) |
| `and` / `or` short-circuit | S | **W** | **W** | **W** | both sides always evaluated — #777, found while measuring |
| floats | P | P | P | P | `f64 % f64` answers a wrong value on all four — #778; wasm treats `f32` as `f64` |
| locals, globals, consts | S | S | S | P | one slot per *name* for the whole function on the twins (shadowing shares it) |
| `if` / `while` / `loop` / range `for` | S | S | S | S | |
| `for`-in over an iterable | S | P | P | P | |
| `break` / `continue`, labeled, with a value | S | P | P | P | |
| scalar calls | S | S | S | S | aarch64/riscv64 pick the **first** function with a matching name — no arity/type check |
| aggregate args and returns, sret | S | P | P | P | three different conventions (aarch64: ≤8 words in `x0..x7`, else sret) |
| C ABI (`extern`, SysV classification) | S | P | P | P | `src/lower/abi_c.al` is x86-only |
| `@abi(syscall)` | S | **LINK** | **LINK** | T | `lib/std/os.al` passes x86_64 syscall numbers |
| structs, whole-value assign | S | P | P | P | |
| arrays, bounds checks | S | S | S | P | ~40 separate inline bounds-check sites on x86 |
| slices, strings | S | P | P | P | twins: `str` only as a `print` argument |
| pointers, `&`, deref | S | P | P | T | |
| enums, payloads, `@repr` tags | S | P | P | P | twins store a full-word tag, ignore `@repr` width |
| `match` (value, statement, payload binding, ranges) | S | P | P | P | range arms trap on all twins |
| `?` | S | T | T | P | wasm picks the success variant by the names `Some`/`Ok` |
| brands, `T(v)` constructors, `@convert` | S | T | T | T | |
| `size(T)`, `align(T)` | S | T | T | T | |
| `@endian`, `@offset`, `@packed` | S | **W** | **W** | **W** | |
| generics / monomorphisation | S | P | P | P | three private monomorphisers |
| comptime `if` / `for` / `match typeinfo` | S | P | P | P | three private folders |
| fn values, lifted lambdas, indirect calls | S | P | P | P | no indirect call (`blr`) on aarch64 |
| overloads, operator functions | S | **ASM** | **ASM** | **ASM** | unmangled (#475) |
| package roots via the emit verbs | S | **LINK** | **LINK** | **ASM** | |
| `asm`, raw `jmp`/`@label`, `@abi(naked)` | S | P | P | – | a target capability by the spec, never portable |

### 2.4 The duplicated decisions

Each row is one decision the language makes once and the compiler makes four times.

| decision | x86_64 | aarch64 / riscv64 | wasm | observed drift |
|---|---|---|---|---|
| width and signedness of an expression | `expr_type_span`, `is_signed_expr`, `is_unsigned_expr`, `infer_local_scalar_type` | `a64_/rv_operand_signed_dep`, `_operand_unsigned`, `_operand_narrow` | `wat_operand_signed_dep`, `wat_bin_init_signed` | #764, #765, #766, #707 |
| signed vs unsigned compare | `is_unsigned_cmp` | `a64_/rv_cmp_unsigned` | `wat_cmp_unsigned` | #766 |
| narrowing after narrow arithmetic | `emit_int_narrow_reg`, `emit_shift_narrow_result` | `a64_/rv_emit_narrow`, `_emit_narrow_trap` (no shift-narrow step) | `wat_narrow_pre/post`, `wat_narrow_trap_check` | `unchecked_narrow_shift_wrap`, MISSING-TRAP |
| checked guard formulae and the `unchecked` scope | `emit_gas` Bin arm, `emit_routed_int_guard`, **and again** `src/lower/ir.al:260-362` | `emit_a64_arith`, `A64_CHK` / `RV_CHK` | `WAT_CHK`, formulae copied from `lib/base/num.al` | |
| short-circuit `and`/`or` | branches (`src/lower.al` ~16807) | eager `and`/`orr` | eager | #777 |
| slot assignment | `collect_slots` (per binding) | `a64_/rv_local_scan` (per **name**) | `local_slot_scan` (per name) | shadowing shares a slot on the twins |
| monomorphisation | `lower/mono.al` + worklist in `emit_program` | `a64_/rv_inst_add` (≤3 type params, 512 entries) | wasm's own (≤3 leading type params) | `generic call: unresolved type-arg` |
| comptime folds | `lower/ctfold.al` `comptime_cond_eval`, `ct_bound_fold` | `a64_/rv_comp_cond_fold`, `_comp_range_bound` | `wat_comp_cond_fold`, `wat_comp_range_bound` | #672 |
| `match` dispatch, variant-arm expansion | `lower/enum_match.al` `expand_variant_arms`, `emit_enum_match` | `emit_a64_/rv_match_arms` | `emit_wat_match_arms` | #577 shapes |
| `?` success variant | `try_success_disc` | – (traps) | `wat_try_success_disc` (by name) | |
| enum size for generic instances | `enum_inst_words` | `enum_inst_words` | `1 + enum_max_arity` (not instance-aware) | |
| callee choice, overloads, symbol names | `callee_decl_idx`, `overload_resolve_idx`, `emit_generic_label` | first name match, `<module>__<name>` | `$name__<paramtypes>` (written twice inside `wat.al`) | #475, ASSEMBLE |
| aggregate call convention | `fn_returns_sret`, `emit_struct_to_sret`, `abi_c.al` | `a64_ret_struct_words`, `a64_ret_sret_words` | by address, tuples 1..7 words | CRASH rows |
| located refusals of invalid programs | 232 sites in `src/lower.al` | – | – | ACCEPTS 233 rows |

`scripts/idiom_gate.sh` sees part of this — its baseline carries SCAN/TABLE clusters for
`emit_a64_expr`/`emit_rv_expr`/`emit_wat_expr`, `emit_*_fn`, `*_comp_range_bound`, `*_ann_span`, the
export-name cluster and the digit cluster — but it cannot see the `*_operand_signed` / `*_narrow_trap`
triplets: they share too few literals to score. The duplication the IR removes is larger than the gate
can measure.

### 2.5 What `src/lower/ir.al` models, and what it bypasses

`src/lower/ir.al` (1 789 lines) with `src/regalloc.al` is an **x86-only machine IR**, not a semantic
one:

- **Representation.** Parallel fixed-size arrays of at most 64 instructions, 32 virtual registers and 16
  labels. Operand kinds: immediate, physical register, virtual register, symbol, frame slot. The op set
  is x86's: `mov add sub imul cmp mul call ret jmp jcc label udiv idiv ud2 load and or xor shl shr sar
  lea` plus three *barriers*. Flags-based condition codes (`jno`, `jnc`). No blocks, no SSA, no types:
  every value is a 64-bit word, and signedness and checked-ness are decided while lowering and baked into
  which opcode is emitted.
- **Eligibility.** `is_scalar_leaf_shape` (ir.al:1666-1789) accepts only non-generic, non-overloaded,
  non-exported functions of ≤6 parameters of the native 64-bit scalar types (`u64 usize i64 isize bool`),
  with no narrowing, no `match`, `loop`, `break`/`continue`, `if` expression, aggregate literal, index,
  deref, `?`, float, lambda or comptime, and within a size budget. It re-walks everything its lowering
  will do, as a predicate — the same decisions, twice.
- **Bypass.** Anything else inside an accepted function becomes a *barrier*: modelled scalars are stored
  back to their frame slots, the statement or expression is printed by the text emitter
  (`emit_gas`/`emit_stmts`), and the IR resumes. That barrier mechanism is the useful precedent for the
  migration below.
- **Verification.** None beyond "no vreg leaked" and capacity panics. No counters: how many functions it
  takes is unmeasured; `ALATYR_RA=0` (read from `/proc/self/environ`) turns it off.

What carries over: the linear-scan allocator and the renderer become the back half of the x86 selector.
What does not: the op set (x86-shaped), the fixed capacities, and the predicate-plus-lowering pair.

### 2.6 Found while measuring

- **#777** — `and`/`or` do not short-circuit on aarch64, riscv64 and wasm. `t or bump()` answers 43
  where x86_64 answers 42; `i < 2 and a[i] > 0` traps on the twins. No corpus fixture has that shape, so
  every manifest row agrees.
- **#778** — `f64 % f64` passes `check` and answers a wrong value on all four backends (decision needed:
  reject or define).

---

## 3. The IR

### 3.1 Where it sits

```
parse → sema (records types) → comptime/`when` fold for THE target → mono worklist → DCE
      → IR build (one per function instance) → IR verify → per-target instruction selection → text
```

Everything up to "IR build" is **one** front half, run identically for every target; the only input that
differs is the target (so `when target.arch == …` and `comptime if` fold against the real target, not
against x86). The IR builder is the single place where a language construct becomes machine-level
meaning. After it, nothing may consult the AST, the source text or a type span: a selector sees only
the IR.

The IR is **private to the compiler** (spec `90-codegen.md` §1.2): no surface exposes it to programs.
A dev verb that prints it for fixtures is proposed in §8 (D5).

### 3.2 Types

IR types are **kernel** types. Brands, named types, aliases and generic parameters are erased before
the IR exists (`lower_layout::brand_underlying`, `alias_rhs`, the mono substitution); the verifier
refuses any other type.

| IR type | meaning |
|---|---|
| `i8 i16 i32 i64` | integers of that width, **with their signedness recorded on the value** (`s`/`u`) |
| `bool` | 0 or 1 |
| `ptr` | a machine address (64-bit on the three register targets; see §6 for wasm) |
| `f32 f64` | IEEE floats |

Aggregates (structs, arrays, enums, tuples, slices, `str`) are **never IR values**. They live in memory —
a frame object, a global, or behind a pointer — and the IR manipulates their addresses. Their layout
(size, alignment, field and payload offsets, tag width and values, `@endian`, `@offset`, `@packed`,
`@repr`) comes from `lower_layout`, once, at build time, and appears in the IR only as byte offsets,
widths and byte-order flags.

**Canonical form.** Every integer value is held as a 64-bit word. A value of a narrow type (`i8`…`i32`)
is always *canonical*: sign-extended from its width if signed, zero-extended if unsigned. The builder
restores canonical form after every operation that can break it by an explicit `ext` (wrapping) or
`fit` (checked) — so **narrowing is an IR operation, never a selector's afterthought**. This one rule
removes the whole "narrow result not narrowed on the twins" class.

**Signedness on the value, and on every op that depends on it.** Division, remainder, right shift,
ordering compares, overflow checks, extension and int↔float conversion each spell `s` or `u`. The
builder picks it from the operand's kernel type; the verifier checks that it agrees (§5, V4). No
selector ever infers signedness, and there is no "unknown" default to drift.

### 3.3 Values, variables and frame objects

- **Virtual registers** (`%n`) hold scalar values. They are *variables*, not SSA: a vreg may be assigned
  more than once, which keeps the builder simple and avoids φ-nodes across structured regions. Each
  source binding gets its own vreg (shadowing never shares one).
- **Frame objects** (`$k`) are per-function memory with a size and alignment: aggregate locals,
  address-taken scalars, spill-proof temporaries, sret buffers. `addr $k` yields their address.
- **Globals and rodata** are symbols with a layout; `addr @sym` yields their address.

**Aggregate temporaries are frame objects, one per use, never a shared pool.** Every aggregate value
the program creates without naming it gets **its own** frame object, sized from `lower_layout` when
the IR is built: a constructor in argument position, a call's aggregate result (the sret buffer), a
`match` scrutinee that is a call, a returned `Result(S, E)` staged before dispatch. A temporary lives
for the statement that creates it; a nested constructor inside another constructor's argument is a
**different** object, built before the outer one reads it. Today's emitters use shared staging areas
instead — wasm's single `$__tmp` block, the twins' aggregate staging, x86's "aggregate-value call-arg
temp pool" and fixed-size scratch — and three open defects are exactly that:

- **#769** — `g(S(a = 42, b = g(S(a = 7, b = 9))))` answers the *inner* constructor on
  aarch64/riscv64/wasm (and the enum form on wasm): the inner constructor reuses the outer one's
  staging area before the outer call reads it. Distinct frame objects make the overwrite impossible.
- **#771** — x86_64 stages a 3+-word `Result(S, E)` returned into a `match` into scratch that is too
  small, and the excess words land on a neighbouring local. In the IR the staging object's size is the
  layout's size by construction, and verifier rule V6 (every access lies inside its frame object) turns
  any mismatch into a located build error instead of a clobbered local.
- **#772** — x86_64 refuses `g(mk(), g(E.A(1), 42))` with "aggregate-value call-arg temp pool
  overflow": a fixed pool, not a language limit. Frame objects have no pool to overflow.

The frame size is the sum of the objects a function needs (a selector may overlap objects whose
statements do not overlap — that is placement, spec `90-codegen.md` §3.3, never semantics).

### 3.4 Operations

Arithmetic ops carry a **mode**, which is where the checked/unchecked decision lives:

- `wrap` — two's-complement at the type's width (the builder follows it with `ext` for narrow types);
- `chk` — traps (`trap overflow`) when the mathematical result does not fit the type;
- `hw` — the `unchecked` hardware-defined operation (spec `00-overview.md` §4: "dangerous operations
  have **hardware-defined** behavior"); only `/` and `%` have a distinct `hw` meaning, see D1.

| group | ops |
|---|---|
| constants | `const T imm`, `fconst T bits`, `addr @sym`, `addr $k`, `fnaddr f` |
| integer | `add sub mul` ·mode · `div rem` ·`s/u`·mode · `and or xor not neg` · `shl shr` ·`s/u`·mode (a `chk` shift traps on a count ≥ width) · `rotl rotr` |
| width | `ext T←T` (wrap to a narrower type, or widen), `fit T←T` (checked narrow: trap if it does not fit), `trunc` for bool |
| compare | `cmp eq ne lt le gt ge` ·`s/u` → `bool`; `fcmp` → `bool` |
| float | `fadd fsub fmul fdiv`, `fneg`, `itof`·`s/u`, `ftoi`·`s/u`·mode, `fext fdemote`, `bits` (int↔float reinterpret) |
| memory | `load T [a + off]` (width from `T`, extension from its sign), `store T [a + off], v`, `bswap T` (for `@endian(big)`), `copy dst, src, n, align`, `zero dst, n` |
| address | `gep a, idx, stride` (no check), `bound idx, len` (`trap bounds` if `idx ≥ len`) |
| calls | `call f(args) → rets`, `call_ind v(args) → rets`, `call_c f(args)` (foreign ABI), `syscall nr, args → ret` |
| control | `block L { … }`, `loop L { … }`, `if c { … } else { … }`, `br L`, `br_if c L`, `switch v [k → L…] default L`, `ret [v]`, `trap kind`, `trap_if c kind` |

`switch` is the `match` dispatch primitive: the selector may lower it to a compare chain, a jump table,
or wasm's `br_table`, but its semantics (source order, first match wins, `default`) are fixed here.

### 3.5 Control flow is structured

Alatyr's portable control flow is structured (spec `60-control-flow.md`, "Backend scope (CG-4): the
**structured** kind below is portable across all backends"), and wasm requires it. So the IR keeps it:
`block`, `loop` and `if` are nested regions; `br L` leaves the enclosing `block L` or restarts the
enclosing `loop L`; labeled `break`/`continue` are `br` to the region the parser already resolved by
depth. Register targets lower regions to labels and jumps trivially; wasm maps them one to one.
Nothing needs a relooper.

Raw transfer (`jmp`, `@label`), `asm` and `@abi(naked)` are a **target capability** by the spec and are
not portable — "on a structured/VM backend … they are a compile error" (same passage); the IR does not
model them (§4, last row).

### 3.6 Traps

Every trap names a **kind** and carries the **source span** of the construct that owns it:

`overflow` · `div_zero` · `div_overflow` · `shift_range` · `narrow` · `bounds` · `match_no_arm` ·
`unwrap` · `require` · `panic`

The kind is what makes a trap located: the selector emits the target's trap instruction (`ud2`,
`brk #0`, `ebreak`, `unreachable`) with the kind and location as the adjacent comment, so
`xbackend_diff.sh --sites` stops having to borrow causes between backends.

### 3.7 Calls and the Alatyr convention

The builder decides, once, how an Alatyr-to-Alatyr call passes its values; the selector only maps the
IR signature onto registers or wasm params:

- scalars by value;
- an aggregate argument by the address of a caller-owned copy (the spec's documented byte-copy);
- an aggregate result through a hidden first `ptr` parameter (sret) into a caller frame object;
- the callee symbol — module path, overload suffix, generic instance tag — is computed by the builder,
  once, so all four targets name a function the same way (the ASSEMBLE class and the twins'
  first-name-match go away together);
- `call_c` keeps the Alatyr-level signature and lets the selector apply the **target's** C ABI (SysV
  eightbytes on x86_64, AAPCS64, the RISC-V psABI, wasm's flat params) — the one place a call's shape is
  legitimately per-target;
- `syscall nr, args` is a single op; which trap instruction and registers it uses is per-target, and the
  numbers are the library's concern (D3).

During the migration an IR-built function and a legacy-emitted function must be able to call each
other, so each selector adopts **its target's existing convention** for every signature class it
supports; the convention is unified only when the last legacy caller of that class is gone.

### 3.8 Signedness and width are attributes of the value, derived once

Today signedness is decided **by the shape of the expression**, separately in each emitter: a bare
typed name is recognised, and anything else — a call result, a struct field, an `if`/`match`
expression, `unchecked` arithmetic, a literal-only expression — falls to that emitter's default. The
program generator (#776) found the family this produces, and every member is the same mechanism:

| issue | shape whose signedness is lost | backends wrong |
|---|---|---|
| #725 (closed by a local fix) | signed **call result** as a dividend (`f() / 9`) | aarch64, riscv64, wasm |
| #764 | signed `/`/`%` whose dividend is `unchecked` arithmetic, an `if`, or literal-only (`(0 - 7) % 9`) | all four for three shapes, x86_64 for a fourth |
| #765 | signed **struct field** as an operand (`s.k / 9`) | aarch64, riscv64, wasm |
| #766 | `u64` ordering over an `if`/`match` expression or literal-only `unchecked` arithmetic | three shapes on all four, two on the twins |
| #707 | signedness of an **array element** of a global or a struct field | aarch64, riscv64, wasm (WRONG-VALUE rows) |

The local fix for #725 taught one emitter one more shape; the next shape was already waiting. The IR
removes the question instead:

1. **The type of every expression is decided once, by sema**, and recorded in a side table keyed by the
   expression node (slice 0a). That includes the contextual type of a literal-only expression — a
   comptime number takes the type its context gives it (spec `20-types.md` §2.3), which is exactly
   what #764's `(0 - 7) % 9` needs — and the types of call results, fields, elements and
   `if`/`match` values.
2. **The builder copies it onto the IR value** (`i64 s`, `u64 u`, `i8 s`, …) and never looks at the
   expression's shape. A value's signedness and width flow with the value through `if`/`match` region
   results, `unchecked`, calls and loads; nothing can "forget" them, because nothing re-derives them.
3. **Every signedness-dependent op spells `s`/`u`**, and verifier rule V4 checks it against its
   operands' recorded signedness.
4. **There is no default.** An expression sema left untyped is `NotYet(untyped expression)` in the
   builder (the function falls back and the census counts it); it is never "signed unless proven" or
   "unsigned unless proven".
5. **A differential census comes for free.** Once sema records types (slice 0a, before any emission
   change), a reporting script can compare, for every `/ % >> < <= > >=` in the corpus, `lib/` and
   `src/`, sema's recorded signedness against what each legacy emitter's shape inference answers. Every
   disagreement is a #764-class wrong value found mechanically instead of by a generator's luck.
6. **Library bodies are recorded too.** `check_program` TRUSTS a declaration of an ambient library
   module — it resolves against it but does not refuse a program over its body, so a check gap on a
   stdlib feature cannot reject a well-typed user program. Until slice 1e's prerequisite (a) that also
   meant `lib/` had no records at all: the slice-1e probe measured 561 of the corpus's 676 distinct
   untyped (`VcAbsent`) operand lines at x86's legacy signedness decisions in `lib/`. Now each
   library declaration is checked by `check_decl` exactly as a user one is, **for its records only**
   (`sema_lib_record`): the verdict stays TRUST and the census instruments the walk would move are
   restored. (When this landed the walk ran only when a consumer asked for records; since item 9
   recording is on for every check.) The twins' record run (which always records) does
   not walk library bodies yet (`sema::set_lib_records(false)`): with the walk, their builder selects
   from the IR every library function whose records it completes, which moved 66 corpus outputs and 3
   manifest rows (only the link/assemble diagnostics of builds that already failed; every run
   unchanged) — an oracle transition of its own. What a user-code check would refuse is not dropped;
   it is reported on the census channel:

   ```
   #semalib refused <module>::<decl> |<the declaration's line>   check_decl refused the body
   #semalib head <module>::<decl> |<the line of the head>        a `::` head resolves to nothing (#580)
   ```

   A refused body keeps the records made before the refusal and none after it. Measured over the
   corpus when this landed (after `lib/base/slice.al`'s `bytes_eq`/`hash_bytes` became `pub`: they
   were private and called from `alloc::string`, `alloc::strmap` and `std::os`, which Modules §3
   refuses):

   | finding | bodies | cause |
   |---|---|---|
   | refused | `base::derive::eq`/`lt`/`hash`, `alloc::fmt::display`, `std::os::args`/`env`/`read_cmdline`/`read_environ`, `base::u128::%`/`/`, `base::num::+` ×4 | a local spelled like a declaration of the USER's root module resolves to it (`f`, `sb`, `add`) — only in programs that declare one (#882) |
   | refused | `std::fmt::write_buf_file` | `[u8]` and `Slice(u8)` are two types to sema (#883) |
   | refused | `std::serialize::read_len` | a `match` whose arms all diverge (`return` / `panic`) reads as a missing result (#667) |
   | head | 46 functions of `alloc::*`, `std::fmt`, `std::os` | sibling heads (`strbuf::`, `io::`, `os::`) and `alloc::get` naming base's allocator — the #580 decision |

   After it, 44 distinct untyped operand lines remain in `lib/` (46 match a `lib/` line by text; two of
   them, `i = i + 1` and `k = k + 1`, are the corpus programs' own), all in bodies sema checks once
   generically while the emitter sees a clone: a type function's methods (`base::u128`'s `uint(N)`),
   `comptime if`/`comptime for` branches, and generic instances (`allocate(…, T, …)`, `Option.get`) —
   prerequisite (b).
7. **Code the checker does not check is recorded too.** Measured, prerequisite (b)'s "clones" are not
   clones: the emitter re-walks the one tree — once for the selected `comptime if` branch, once per
   unrolled `comptime for` iteration, once per generic instance — and the nodes it reached without a
   record were the ones `check_stmts` never walks: the condition and branches of a `comptime if` /
   `comptime match` and the body of a `comptime for` (Comptime §8, §9.2; the checker's own gap is
   #889), and a generic call's argument written where an implicit type parameter sits — the receiver
   of `r.expect(m)`, which the UFCS desugar writes `expect(r, m)` and the checker skipped as the type
   argument `T` (#887; every `allocate(…).expect(…)` of `lib/`). Whenever records are wanted, sema
   walks that code for its records only (`sema_ct_record`), in the scope it appears in, with the same
   `check_stmts`/`check_expr`:

   - a `comptime if` whose condition `guard_fold` (the `when` evaluator) decides walks the selected
     branch; an undecided one — its condition depends on an instance — walks both (a record on a node
     no instance emits is never read); a `comptime match` walks every arm, its bindings in scope;
   - a `comptime for` walks its body once: over a range the variable is bound as a range `for` binds
     it, over a pack or a type's members it is untyped. A node whose type varies per iteration or per
     instance (a pack element, `v.(f)`, a `T` value) gets the one reading the body has, `VcUnknown`
     where no single type holds — a gap for prerequisite (c), never a guess. The table stays keyed by
     node, and each node gets the one record its single reading has;
   - the walk is a transaction, as a capability query is: its locals, sticky diagnostics,
     definite-assignment state and census instruments are put back, and a `compiles`/`resolves` query
     inside it is answered but not folded into the tree (lower answers it per iteration). The verdict
     does not move; what the walk refuses is reported:

   ```
   #semact refused |<the line of the walked condition, loop variable or argument>
   ```

   Measured over the corpus when this landed (2270 sources), the probe's distinct untyped operand lines
   went 161 → 10 (`lib/` 46 → 2, both the corpus programs' own `i = i + 1` / `k = k + 1`; `src/` 0 → 0).
   The 10 are not this class: 8 are in the body of a value-bearing `loop`, which `check_expr` never
   walks (#888), and 2 are the place `deref(deref(pp)).v` of a nested field store, whose place the
   checker does not type (prerequisite (c)). Seven `#semact refused` rows:

   | row | cause |
   |---|---|
   | `test/fmt_comptime.al`, `test/fmt_comptime_for.al` | an immutable local reassigned in a `comptime for` body — accepted today (#889) |
   | `test/query_unselected_branch.al` | the unselected `else` (`no_such_name()`), walked because sema cannot fold `compiles(1)` |
   | `test/comptime_resolves_args.al` ×3 | the checker refuses `resolves(f, args…)` (#890) |
   | `test/single_hash_comment.al` | `target.arch != Arch.i386`: sema knows no variant `i386` |
8. **What the checker leaves unknown is recorded too** (prerequisite (c)). `check_expr` answers a `Ty`
   it can afford to be tolerant with: it resolves names among the declarations before the one being
   checked, keeps a pointer's pointee only when it is a struct or an enum, and leaves a qualified or
   generic callee's result, a `deref`, an element, a payload binding and a value read through an
   unknown base `UNKNOWN`. That stays the verdict's business. Beside each node's value type the
   recorder now keeps the **spelling** of that type (`ir::TySpell`): the declaration text that names
   it — a parameter's or a field's annotation, a callee's `-> R`, a variant's payload component, a
   pointer's pointee — read through the resolvers the checker and the layout already use
   (`type_decl_index`'s Modules §3 rank, the visibility check's module-segment match, a module alias
   followed one hop, `ptr_target_pointee`, `typearg_at`). The value type of a field, a pointee, an
   element, a tuple component, a `?` payload, a match binding or a call result is derived from it.

   - **Scope.** A spelling read in a generic declaration (a generic callee's result, a generic
     struct's field, a generic enum's payload) carries that declaration and its instance: the
     `( … )` group of the struct instance it was reached through, or the call that reached it. A
     bare type parameter is replaced by what the instance binds it to — the written type argument,
     or, with the type arguments omitted, the type matching the callee's parameter types against the
     arguments' spellings gives it (`self : Result(T, E)` against a `Result(Handle(u8), AllocError)`
     binds `T`). This is substitution of a declaration's own parameter, never a type read off an
     expression's shape. A type parameter of the declaration being checked stays one: the record of
     a value of type `T` is `VcUnknown`, because only the instance knows it (below).
   - **Types no text spells** are wrappers of a spelling: a pointer to it (`ptr(x)` of a value), an
     array of it (`[e0, e1, …]`), a view of it (`a[lo..hi]` of such an array); and three builtins:
     the byte view `str`, its byte `u8`, and the native signed integer an unannotated literal
     defaults to (Types §9.1 — an unannotated `[1, 2, 3]`, a value `loop` whose `break`s carry only
     literals, a range of two literal bounds).
   - **Code the checker does not walk** is walked for its records only, as in item 7: a value
     `loop`'s body (#888), a lambda's body (the driver lifts it into a declaration whose captured
     names become untyped trailing parameters; each use of an enclosing local in the body records
     that local's type at the use, the key the lifted capture parameter is declared at), and the place
     of a nested field store (`deref(deref(pp)).v = …`).
   - **Calls.** A syscall-ABI fn is a fn; a type alias names its target; the writing module's own
     alias of a head shadows a module of that name (`strbuf := rt`); a type's name as a head names
     its module (`Option::unwrap_or`); same-named fns are told apart by argument count, by the
     receiver's type head (`r.unwrap()` over a `Result`), or — `when` alternatives of one module —
     by sharing one result spelling; a fn-typed local or field is called through its `fn(…) -> R`;
     `size(T)`/`align(T)` are `usize`; an `atomic::` or `volatile::load` operation reads its
     operand's pointee; an arithmetic operator over an aggregate is the operator fn declared for it.

   Measured with the 1e probe (operand records at x86's legacy signedness decisions, the
   self-build plus every corpus program through x86_64), distinct source lines with an operand sema
   left `VcUnknown`/`VcAbsent`, before → after:

   | set | before | after |
   |---|---|---|
   | `src/` (self-build) | 1958 lines (3601 rows) | **0** |
   | corpus + `lib/` (2272 sources) | 924 lines (13366 rows) | **109** (326 rows) |

   What remains is not a recorder gap of this kind:

   | class | lines | why |
   |---|---|---|
   | the instance's type | 43 | an operand of a type parameter's type (`a < b` over `T`, `deref(p)` of a `ptr(K)`), a pack element or `v.(f)`: one node is emitted once per instance, and no single record holds. Only the instance knows the type |
   | `typeinfo` members | 6 | `typeinfo(T).n`, `.fields.len`, `Field.offset`: Comptime §5.1 names the members but not their types |
   | calls of values the checker types as non-functions | 16 | a parameter declared `g : u64` called as `g(x)`, an indexed fn-array element `fs[i](3)`, a `when`-guarded companion value: the call has no declared result |
   | a lambda passed to a higher-order callee | 9 | the driver specializes it into the callee instead of lifting it, so its captures are never declared parameters |
   | the rest | 35 | each a shape the recorder does not read yet: a tuple literal's type, a payload of a generic enum matched without its instance, a field of a generic struct inferred through an implicit type argument, … |

   The same measurement shows the next prerequisite's input: with more operands typed, 1977 rows of
   the self-build compare or combine a signed with an unsigned operand (1178 before) — prerequisite (d).
9. **One operator's integer operands share a signedness** (prerequisite (d)). Types §4.2 classes a
   signed<->unsigned change as a **numeric** conversion, §4.3 makes only **widen** implicit, and §4.5 /
   §5.3 make an operator an ordinary overloadable function with no `iN`-and-`uM` signature; Types §12
   item 5 is the conformance rule. With no context an integer literal is the target's native signed
   integer (Types §9.1, Declarations §3.4: "a literal that needs a non-default type with no context
   MUST be annotated or constructed"). So a binary operator other than `and`/`or`/`not` whose two
   operands sema recorded as integers of opposite signedness is ill-formed, and `check_expr` refuses
   it after recording (`sema_mixed_signedness`, diagnostic class `SIGNEDNESS_CONVERSION_DIAG_MARKER`,
   "implicit signed/unsigned conversion …"), on all four backends at once. A literal-only operand is
   `VcLit`, never an integer of its own, so `n + 1` and `0 - k` stay accepted (§2.3). `unchecked`
   changes what an operation does on overflow, never which operations exist, so it does not exempt a
   pair.

   - **The verdict reads the records, so recording is on for every check** (`ir::STY_ON` starts true).
     A refusal that fired only when a consumer had asked for records would make `check` and `build`
     disagree with `x86-ir` and the census. Measured on the self-build, records cost ~35% of a
     self-compile (200 s → 271 s with the census channel open as well).
   - **Scope.** The rule covers binary operators. The other sinks where the same implicit numeric
     conversion hides — an annotated binding's initializer, an argument, a `return`, a store — are not
     refused yet (`x : usize = k` with `k : i64` still checks); they are the next increment of the
     same rule. A generic body's operand of a type-parameter type is `VcUnknown` (item 8), so a mix
     that only an instance can see (`T` against `usize`) is not refused: Comptime §9.3 checks a generic
     "per satisfying instantiation", which needs per-instance records — the 1e question
     (docs/ir-slice-1.md §7).
   - **Bindings shadow, and the records follow.** The checker kept the FIRST of two same-named `for`
     variables or match payload bindings in its local list (`if local_in(…) {} else { push }`), so a
     second loop's `u64` counter or a second match's `u64` payload was typed as the first one's
     `i64`, and the refusal would have fired on a well-typed program. Each binding is now pushed, so
     the innermost entry is the one `local_lookup` and `sema_vty_var` find (Declarations §6.1;
     `test/signedness_shadow_records.al`).
   - **The tree.** The self-build had 1977 such rows when #903 typed the operands. Each was fixed at its
     root, never by a cast at a site that hides a wrong type: an unannotated literal-initialized local or
     module binding gets the type it is used as (`mut i : usize = 0`, `mut IRP_NBIN : usize = 0`), and a
     frame-slot offset (an `i64`: slots grow downward from `%rbp`) meeting a word count converts the count
     at the site (`dst - i64(k) + 1`). The self-build now has **0** rows; so does `lib/` over the corpus
     (`std::thread::spawn`'s stack length was its one). The seed still reproduces the tree
     (`seed == Stage1 == Stage2`): the change moves the compiler's own GAS only through its own source
     text, never through how it emits, so it owes **no** promotion.
   - **The corpus.** 60 programs mixed. 59 spell the type they meant (`mut acc : u64 = 0`,
     `0..u64(9)`, `xs : [u64; 4] = …`, `z : u64 = loop { … }`) and keep their rows — six twin rows
     improve, since a typed value `loop` now builds the same on aarch64/riscv64 as on x86_64.
     `test/unchecked_mixed_signedness.al` mixed on purpose (the x86 `unchecked` peel's operand-order bug,
     #764's family); the pair is now ill-formed, so it is a `build_reject_has` fixture, with
     `signedness_mixed_compare`, `signedness_mixed_literal_default` and the accepted forms in
     `signedness_spelled_ok`.

**What slice 1 closes structurally.** Slice 1 (scalar core) consumes the recorded type, so on the three
twins it closes the scalar shapes of the family: **#764** (all dividend shapes are scalar), **#766**'s
`if`/`unchecked`/literal-only shapes, and the call-result shape of **#725** for good. **#766**'s
`match`-expression shape closes with slice 4 (the `match` value is built there), **#765** and **#707**
with slice 3 (field and element loads carry the layout's declared type). x86_64 does not move to the
IR until slice 9, so slice 1 also includes one legacy change: **x86's `is_signed_expr` /
`is_unsigned_expr` / `is_unsigned_cmp` answer from sema's side table** and lose their shape-based
fallback. That closes #764 and #766 on x86_64 at the same time as on the twins. If the compiler's own
source contains an affected shape its GAS moves and a seed promotion is owed; slice 0a's differential
census says in advance whether it does.

---

## 4. How each construct lowers

| construct | IR |
|---|---|
| integer `a op b` | `op`·mode on the operands' kernel type; a narrow type adds `ext` (wrap) or uses `fit` (checked) |
| `/`, `%` | checked: `trap_if (cmp eq b 0) div_zero`, and for signed `trap_if (a == MIN and b == -1) div_overflow`, then `div`/`rem`·`s/u`; `unchecked`: `div`·`hw` (D1) |
| shifts | `shl`/`shr`·`s/u`·`chk` (count checked against the *type's* width, not 64) |
| `uN(x)`, `iN(x)` | `fit` (checked narrow), `ext` (widen, or narrow inside `unchecked`) |
| `bitcast` | scalar↔scalar: `bits` or `ext`; to an aggregate: `store` into a frame object |
| `and`, `or`, `not` | `if` regions assigning a `bool` vreg — **short-circuit by construction** |
| `if` / value `if` | `if c { … %r = … } else { … %r = … }` |
| `while`, `loop`, range `for` | `block L_exit { loop L_top { … } }`; range `for` steps with `add wrap` after a bound test |
| `for x in xs` | the desugared index loop with `bound` |
| `break v` / `continue` | assign the loop's result vreg, `br L_exit` / `br L_top` |
| `return` | run pending `defer`s (LIFO), `ret` |
| local, param | a vreg; a frame object when its address is taken or it is an aggregate |
| global, const | `addr @sym` + `load`; a comptime-known const is `const` |
| struct literal, field read/write | `zero`/`store` at `lower_layout` offsets into a frame object; `load`/`store` at the field offset; `bswap` for `@endian(big)` fields |
| array/slice index | `bound idx, len` (checked scope) then `gep` + `load`/`store` |
| whole-aggregate assign, aggregate argument | `copy dst, src, size, align` |
| enum construct | `store` tag (width from `@repr`) + payload fields at `variant_payload` offsets |
| `match` | evaluate the scrutinee once; `switch` on the tag or scalar in source order; range arms as compare chains; payload bindings are `load`s from the matched variant's offsets; an arm body per region; `default` → `trap match_no_arm` (D2) |
| `e?` | `load` tag; `br_if` success → continue with the payload; else build the error result (through `@convert` when the enclosing return type differs) and `ret` — the success variant comes from the enum's declaration, never from its name |
| brand / named `T(v)` | the kernel value, plus the brand's declared checks (`@require`) as `trap_if … require` |
| `@convert` | a `call` to the resolved conversion function |
| `size(T)`, `align(T)`, `typeinfo` facts | `const` from `lower_layout` |
| generics | one IR function per mono instance; types substituted before build |
| comptime `if` / `for` / `match typeinfo` | already folded or unrolled by the front half; the IR never sees comptime |
| lambdas, fn values | lifted functions; `fnaddr f`, `call_ind` |
| `str` literal | `addr @rodata` + length, as a two-word aggregate |
| `@abi(syscall)` call | `syscall` |
| `extern` call | `call_c` |
| `asm`, `jmp`, `@label`, `@abi(naked)` | **not IR.** A function containing them is emitted by its target's raw path; on wasm it is a located compile-time refusal (a target capability the backend lacks) |

---

## 5. The verifier

The verifier runs on every function after the builder and before any selector, in every build (it is
linear in the function's size). A failure is a **located internal error** — `alatyr: internal: IR
verify <rule> in <function> at <file>:<line>:<col>` and a nonzero exit — never emitted code. A malformed
lowering therefore becomes a refusal on all four targets at once instead of a wrong value on one.

| rule | checks |
|---|---|
| V1 types | every vreg has one IR type; every operand's type matches its op's signature |
| V2 kernel only | no brand, alias, generic parameter, comptime or unresolved type reaches the IR |
| V3 canonical narrow | an op producing a narrow type is canonical-preserving (`and or xor` of canonical operands, `load`, `const` in range, `ext`, `fit`) — wrapping arithmetic on a narrow type must go through `ext`/`fit` |
| V4 signedness | every `s/u` op agrees with its operands' recorded signedness (an explicit `ext` or `bits` is the only way to change it) |
| V5 definite assignment | every vreg is assigned on every path that reaches a read (a structured forward dataflow) |
| V6 memory | `load`/`store` widths ∈ {1,2,4,8}; a frame-object access lies inside the object; `copy`/`zero` sizes are non-negative constants or vregs |
| V7 control | every `br` targets an enclosing region; labels are unique; nothing follows a terminator in a sequence; a function with a result returns or traps on every path |
| V8 calls | arity and types match the callee's IR signature; an sret callee receives a frame-object address |
| V9 traps | every `trap`/`trap_if`, and every `chk` op, carries a kind and a source span |
| V10 checked scope | a `chk` op never appears inside a region the builder marked `unchecked`, and a `wrap`/`hw` arithmetic op on a checked type appears only inside one |

V3, V4 and V10 are the rules that would have caught #764–#766, `unchecked_narrow_shift_wrap` and the
MISSING-TRAP rows as located build errors instead of silent values.

---

## 6. How the four targets consume it

Each target gets one **instruction selector**, a child module next to its current emitter
(`src/lower/isel.al`, `src/aarch64/isel.al`, `src/riscv64/isel.al`, `src/wat/isel.al`). A selector is
target text only: register names, instruction spellings, the trap instruction, the frame and the
call-register mapping. It never reads the AST.

| target | vregs | control | notes |
|---|---|---|---|
| x86_64 | the existing linear-scan allocator (`src/regalloc.al`), with its fixed capacities lifted; its current op set becomes the selector's *machine* IR | regions → labels | `chk` add → `add; jo trap`; `ext`/`fit` → `movs*`/`movz*` + compare; `ud2` for traps |
| aarch64 | frame slots first (as today's stack machine), the allocator later | regions → labels | `sxtb/uxtb…`, `adds`+`b.vs`, `brk #0` |
| riscv64 | frame slots first, the allocator later | regions → labels | no flags: overflow by compare sequences; `ebreak` with a `#` comment |
| wasm | wasm locals (`i64`/`f64`; `f32` stays `f32`) | regions → `block`/`loop`/`if`/`br`/`br_table` one to one | frame objects on a **shadow stack** in linear memory, popped on return (today's bump allocator never reclaims); `ptr` is an `i64` wrapped to `i32` at each access; `_start` passes `result & 255` to `proc_exit` |

A shared, target-independent IR is also what makes a later optimisation or a fifth target cost one
selector instead of one more emitter.

---

## 7. Migration plan

### 7.1 Rules that hold at every step

1. **Fallback, never refusal, while migrating.** Every selector falls back to its target's legacy
   emitter for whatever the builder does not yet accept, and says why (`NotYet(construct, span)`). A
   program that runs today keeps running; no slice turns a twin's run into a compile refusal.
2. **Fallback granularity.** Per *function* in slice 1 (simplest, and measurable as "functions built
   through the IR" per target). From slice 3 on, where function-level coverage would stall on mixed
   bodies, per *statement* through barriers in the style of `src/lower/ir.al`: the selector stores live
   vregs back to the legacy emitter's name-keyed frame slots, lets the legacy emitter print one
   statement, and resumes.
3. **x86_64's default emission does not move until the flip (7.4)** — with one exception, slice 1's
   signedness queries answering from sema's side table (§3.8). Otherwise x86 goes through the IR only
   on an opt-in dev path (D5), so the compiler's own GAS — and therefore
   `seed == Stage1 == Stage2` — is untouched by slices 0–8 unless slice 0a's signedness census shows
   the compiler's own source has a #764-class shape (then slice 1 owes one promotion, and the census
   says so before it starts). The twins are free to change, because the
   compiler is built for x86 only.
4. **Measured predictions.** Every slice PR states, before its gate, the exact manifest rows it expects
   to move (joined on `(backend, path)`) and that no other row moves. Twin rows moving from a
   disagreement to the x86 value are intentional oracle transitions, so each slice is **gated alone**
   and the maintainer regenerates `scripts/corpus.manifest` in its own commit (AGENTS.md).
5. **The x86 differential.** From slice 1 on, a reporting script (`scripts/ir_diff.sh`, proposed) builds
   every corpus source with x86-via-IR and compares against the committed x86 row. It reads the manifest
   and writes nothing, like `xbackend_diff.sh`. It is the proof that the builder means what the reference
   lowering means before any twin relies on it — and it measures x86 coverage long before the flip.
6. **A census per slice.** `scripts/ir_census.sh` (proposed, reporting-only) prints, per target, how many
   functions of the corpus, `lib/` and `src/` go through the IR, and the `NotYet` reasons ranked. A
   slice is done when its family's reasons are gone from the census.
7. **Deleting old copies.** A legacy family is deleted from an emitter when the census shows that no
   function and no barrier reaches it on that target. Families high in the tree (calls, `match`, `?`,
   syscalls) empty first; leaf families (scalar arithmetic) are reached from inside every legacy
   statement and so are deleted last, together with the legacy emitter itself.

### 7.2 The slices

The row counts are the current disagreements the slice is expected to remove; they come from §2.2's
site families and the named paths in §2.1. "Catch-all share" is the part of the 370 `unsupported expr`
rows whose construct the slice owns; slice 0 makes those trap comments name the construct so each slice
can claim its share exactly.

| # | slice | builder + selectors | expected to eliminate | deletes (when the census allows) |
|---|---|---|---|---|
| **0a** | IR core, inert | `src/ir.al` (types, ops, arena-backed storage — no fixed capacities), printer, verifier, a builder that answers `NotYet` for everything; sema records each expression's resolved type (width, signedness, contextual literal types) in a side table; `ir_census.sh`; the signedness differential census (§3.8); trap comments name their construct | nothing: x86 GAS byte-identical (fixpoint holds), twin output differs only in trap comments (manifest identical). Deliverable: the census's first column, and the split of the catch-all | – |
| **0b** | one front half | the twin verbs run the x86 front half — sema over the emitted tree (fixing the cache aliasing that forced the separate run), `when` folding for the real target, the mono worklist, package roots through the package pipeline | the package-root rows: **138 LINK + 70 ASSEMBLE = 208 rows** (69–70 paths); part of ACCEPTS where a twin now meets the same front-half refusal | the twins' private front-end glue in `d_compile_file_multi` |
| **1** | scalar integer core + control flow | all integer widths, `wrap`/`chk`/`hw`, `ext`/`fit`, conversions, shifts, compares, short-circuit `and`/`or`/`not`, `if`, `while`, `loop`, range `for`, labeled `break`/`continue` with values, `return`, scalar locals/params/globals/consts, direct scalar calls, `unchecked`; wasm's `& 255` exit byte; signedness and width as value attributes from sema's side table, and x86's legacy signedness queries answering from the same table (§3.8) | WRONG `unchecked_narrow_shift_wrap` (3 rows); MISSING-TRAP `checked_index_overflow`, `checked_index_bind_ovf`, `checked_narrow_shift_oob` (6 rows) and their wasm LOUD rows (3); LOUD `unchecked_sub_ovf`, `int_literal_float_context_f32` (2); scalar-CF traps (7); the value-`loop` part of the catch-all; the four `unchecked` division paths (8 rows) **if** D1 says they must agree; structurally, on all four backends: #764, #766 (`if`/`unchecked`/literal shapes), #725's call-result shape; and #777 | – (the scalar arms stay while legacy statements reach them) |
| **2** | calls, ABI, symbols | the Alatyr convention (scalar, aggregate-by-address, sret), `call_c` with per-target C ABI, `syscall`, one mangling (module, overload, operator, instance tag) | syscall: **242 LINK + 109 TRAP = 351 rows**; the overload/operator ASSEMBLE rows (#475); twins' first-name-match wrong-callee risk; wasm `unknown import` LOUD rows (3) per D4 | twins' `*_callee_defined`/`*_emit_bl_target`, wasm's two copies of the overload suffix |
| **3** | aggregates, places, layout | frame objects, field/index/deref places, `copy`/`zero`, bounds, aggregate literals, `str`/slices as two-word aggregates, `@endian`/`@offset`/`@packed`/`@repr`, `size(T)`/`align(T)`; statement barriers begin | aggregate-place **512 rows**; `size(T)` **81 rows**; WRONG `endian_struct`, `endian_offset_struct`, `packed_attr_param`, `fmt_agg_body_comment`, `signedness_global_array`, `signedness_struct_field_array`, `slice_field_compare` (19 rows); CRASH `agg_arr_elem_arg`, `sret_discard_statement` (3); catch-all `StructLit`/`ArrayLit`/`StrLit`/`Slice`/`AddrOf`/`Deref` share; structurally: #765 and #707 (typed field/element loads), #769, #771 and #772 (one frame object per aggregate temporary, §3.3), #773 | twins' `*_operand_signed_dep` field paths, sret stores, byte-tier helpers |
| **4** | enums, `match`, `?` | tags and payloads, `switch`, payload binding, range arms, `?` by declaration | `match` **174 rows**; enums **39 rows**; catch-all `EnumLit`/`Try` share; #766's `match`-expression shape; `comptime_enum_eq` CRASH if it is the tag path | `emit_*_match_arms`, `wat_try_success_disc` |
| **5** | brands and conversions | brand constructors with their `@require` checks, `@convert`, bitcast to aggregates | brand/conv **82 rows**; LOUD `convert_agg_user`, `convert_to_builtin` (2; they need slice 1's exit byte first) | – |
| **6** | generics and comptime residue | nothing new in the IR — the front half already monomorphised and folded; the twins stop using their private mono/fold | comptime/generic **96 rows**; `for`-in **33 rows**; the generic part of the builtin-callee rows (`unwrap`, `map`, `sort`, `forget`, `len`, `bytes`); `fmt_comptime_match_template`, `fmt_comptime_arm_template`; the `when_guard_binding` traps | `a64_/rv_inst_add`, `*_comp_cond_fold`, `*_comp_range_bound`, wasm's mono |
| **7** | fn values | `fnaddr`, `call_ind`, lifted-lambda values | fn values **26 rows**; catch-all `Lambda` share | – |
| **8** | floats | `f32` kept as `f32`, conversions, float globals on wasm, `%` per #778's decision | floats **19 rows** | – |
| **9** | the x86 flip | x86 default emission moves to the IR family by family (7.4); `src/lower/ir.al`'s predicate and lowering are deleted, its allocator stays | the ACCEPTS rows whose refusal was x86-lowering-only (the refusals move into the builder or sema) | `src/lower.al`'s semantic core, then each twin's legacy emitter as its census reaches zero |

The remaining families — `unresolved var` (61 rows) and the non-generic builtin callees (`movq`,
`checked_add`, `wrapping_add`) — are attributed by slice 0's census before any slice claims them; the
design does not guess.

**Expected total.** Slices 0b–8, with the census-attributed remainder above, target every TRAP, LINK,
ASSEMBLE, WRONG-VALUE, MISSING-TRAP, CRASH and LOUD-EXIT row, i.e. 2 423 of 2 656 rows. What is left
is ACCEPTS (233 rows, closed by moving located refusals out of x86's lowering), the target-capability
rows (`asm`, raw transfer, `naked` — declared per backend, never a disagreement), and whatever D1
declares hardware-defined.

### 7.3 Why slice 1 is small in rows and still first

Slice 1 moves few disagreeing rows (~30 in the corpus) because the scalar core mostly works on the
twins today. It is first because it builds the whole pipeline end to end — typed front half, builder,
verifier, three selectors, the census and the x86 differential — on the constructs where a mistake is
easiest to see, and because every later slice's constructs contain scalar arithmetic.
Its largest effect is outside the corpus rows: with signedness and width attached to the value
(§3.8) it closes the scalar members of the #725/#764/#766 family on all four backends at once, the
family the program generator keeps finding one shape at a time.

### 7.4 The x86 flip, and seed promotions

Moving x86_64's default emission changes the GAS the compiler emits for its own source, so the committed
seed stops reproducing Stage1: each flip step owes a **self-promotion**, which is the integrator's act
(AGENTS.md "Reproducibility"). The flip is therefore last, batched into as few promotions as the
x86 differential allows, and each promotion's normalized seed-to-Stage1 delta must stay describable in
one sentence ("functions of family F are now emitted by the IR selector"). Byte-identity with today's
x86 output is **not** a goal: `ir.al`'s register-allocated output already differs from the text path
for the same functions.

---

## 8. Decisions for the owner

- **D1 — `unchecked` division.** The spec calls unchecked operations hardware-defined
  (`00-overview.md` §4). x86 `div` traps on zero; aarch64 answers 0; riscv64 answers all-ones.
  Either (a) keep `hw` semantics and declare the four `unchecked_*div*` paths per backend
  (`run_a64`/`run_rv64` rows), or (b) define one result in the spec. The IR supports either; (a) needs
  no spec change.
- **D2 — `match` with no arm taken.** The spec makes a non-exhaustive `match` a compile error
  (`60-control-flow.md` §5.1), so `default` is unreachable for a well-typed program. The IR lowers it to
  `trap match_no_arm`. Today x86 falls through (the observed `rc=255`, #544); any program that reaches
  it would move from a value to a trap. Is the trap accepted as the one behaviour?
- **D3 — syscall numbers.** `lib/std/os.al` passes x86_64 numbers (`sys_mmap(9, …)`). The IR op is
  per-target in its instruction, but the numbers are data: a per-target table in the library (`when
  target.arch`), or a symbolic syscall name the selector maps? And on wasm: WASI imports for the few the
  library needs (`fd_write`, `memory.grow` for `mmap`), or a located refusal?
- **D4 — bodyless externs on wasm.** An `extern` the module cannot satisfy is a wasmtime `unknown import`
  at instantiation (LOUD-EXIT). Import from `env` and let the embedder fail (today), or refuse at compile
  time?
- **D5 — the dev surfaces.** The x86 differential and IR fixtures need a way in: an `alatyr ir <file>`
  print verb and an x86-via-IR emit verb (next to `alatyr aarch64 <file>`), or an environment switch like
  `ALATYR_RA=0`. The spec's codegen purity ("no environment", `90-codegen.md` §3.1) argues for verbs.
  Are dev verbs acceptable CLI surface?
- **D6 — where types come from.** This design has sema record the type it already synthesizes for every
  expression, and the builder resolve it to a kernel type through `lower_layout`. The alternative — a
  new type synthesis inside the builder — would be a fifth copy. Sema's `Ty` today is a tag plus a name
  span with a poison-tolerant "unknown"; the census will count the expressions sema leaves unknown, and
  each is a sema gap to close, never a default to pick (§3.8). Accept sema as the single source?
- **D7 — fallback granularity.** Function-level fallback in slice 1, statement barriers from slice 3.
  Alternatively barriers from the start (more coverage sooner, more coupling to legacy frame layouts).
- **D8 — gating cadence.** Every slice carries intentional twin transitions, so every slice PR is gated
  alone and costs one oracle regeneration. Accept that cadence for the migration?

---

## 9. Method

- **Classes:** `bash scripts/xbackend_diff.sh --count` and `--rows` on `a46b5bc`'s committed
  `scripts/corpus.manifest` (2 186 sources). No compiler run.
- **Sites:** `scripts/xbackend_diff.sh --sites <compiler>` on the native x86_64 gate machine, compiler
  built by the seed from `a46b5bc`; 2 385 output rows: 1 849 `SITE`, 380 `LINK`, 141 `ASSEMBLE`, 10
  `LOUD`, 5 `NOSITE`. Families are a regular-expression grouping of the site comment; riscv64 rows whose
  `ebreak` had no comment take the aarch64 comment of the same path. An earlier run of the #763 lane
  on `b8cf45d` gives the same family counts.
- **Support matrix and decision catalogue:** code reading of the four emitters at `a46b5bc`, with
  function names and line numbers as cited, cross-checked against the site families.
- **#777 and #778:** probes built from `a46b5bc` on the gate machine and run on all four backends; the
  programs and their exits are in those issues.
- **Sizes:** `wc -l`.
