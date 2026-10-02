# Shared IR, slice 2 — design note (calls, ABI, symbols)

Status: **design, then code, PR by PR.** Branch `lane/ir-slice-2a` on `main` (`4c48d4e`, slices 0a,
0b, 1a–1d). It refines `docs/ir.md` §7.2 row 2. That row is the authority on scope; this note says how
slice 2 delivers it, in what order, and what each PR is predicted to move before its gate (§7.1 rule
4). It mirrors `docs/ir-slice-1.md`.

## 0. What slice 2 must make true

- **Syscalls.** A bodyless `@abi(syscall)` declaration is a trampoline the shared IR builds as one
  `syscall` op; aarch64 (`svc #0`, number in x8) and riscv64 (`ecall`, number in a7) select it. That
  removes the LINK class (`bl sys_mmap` left unresolved). The numbers are **library data, per target**
  (owner decision D3, ABI §5): `lib/std/sysno.al`, one `when target.arch == …` row per call and arch.
- **One mangling.** The callee of a call is resolved once and named once: the definition and every
  call site of a declaration print the same symbol (`ir::put_fn_symbol`), overloads and operator
  functions included (#475, #844), so the twins' first-name-match wrong-callee risk goes away.
- **`call_c`.** An `@extern` import is called through the target's C ABI on aarch64 and riscv64.
- **wasm: no invented behaviour.** D3 and D4 are spec-silent on wasm (CG-14/FND-6, Modules §7.1), so a
  wasm syscall and a wasm bodyless extern keep today's behaviour (a located trap / `unknown import`)
  and the question goes to the spec proposal (§4).
- **x86_64's default emission does not move** (§7.1 rule 3). Nothing here touches `src/lower*`'s
  default path; the compiler's own GAS links only `rt::sys_*` and `base::process`, neither of which
  slice 2 edits, so no seed promotion is owed.

## 1. What slice 2 does NOT do: the aggregate convention

`docs/ir.md` §7.2 lists "aggregate-by-address, sret" under slice 2. No aggregate value can be built
before frame objects, field places and aggregate literals exist, and those are slice 3. An
aggregate-typed parameter or result therefore stays `NotYet(signature)` in slice 2, and the
aggregate convention (the address of a caller-owned copy, the sret first parameter) lands with
slice 3's frame objects, where it can be measured. The scalar convention is unchanged from slice 1
(`docs/ir-slice-1.md` §3); slice 2 adds `ptr` to the scalar class.

## 2. The PRs (each gated alone, D8)

1. **2a — syscall trampolines, `std::sysno`, pointers as call scalars.**
   - Builder: `ib_build_syscall` (`src/ir/build.al`) builds `%r = syscall %0(%1, …); ret %r` for a
     `DECL_KIND_SYSCALL` declaration; `ptr` is a kernel scalar (`VcPtr → KPtr`) for parameters,
     results, bindings and `==`/`!=`. Pointer arithmetic stays `NotYet` (a place, slice 3).
   - Selectors: `sa_syscall` / `sr_syscall`; the aarch64/riscv64 program loops hand every syscall
     declaration to the selector (the legacy emitters have no trampoline at all, so a refused one stays
     absent, as before). wasm is untouched.
   - Symbols: `ir::put_fn_symbol` is the one `<module>__<name>` spelling (aarch64's legacy label
     delegates to it); a trampoline is named by it on both register twins, because one call is declared
     in several modules (`sys_write` in `std::io` and `std::fmt`).
   - Front half (`driver::d_compile_file_multi`): the `when` guards fold for the twin's real target
     **before** the prune, so a per-target table keeps exactly its row; a qualified module value
     (`std::sysno::MMAP`, whose `Var` span is its tail) is marked reachable and rewritten to its
     declaration's name span; a bare call to the caller module's own syscall declaration is rewritten
     to that declaration's name span. The builder and the legacy call sites resolve a callee by that
     identity first.
   - Sema (records only): a call to a syscall declaration records its declared result, and a literal
     argument takes its parameter's type (`sema_vty_syscall`); the verdict does not read either.
   - Library: `lib/std/sysno.al`; every `lib/std` syscall call site passes `std::sysno::<NAME>`.
     `open` and `fork` have an x86_64 row only (the generic kernel table has `openat`/`clone`), so on
     aarch64/riscv64 a program reaching them fails loudly. `lib/base/process.al` (in the compiler's
     own build) is not touched.
   - Fixtures: 111 corpus programs declared their own `sys_mmap` and passed x86_64's number `9` (and
     four `sys_write(1, …)` calls). By ABI §5 that number is the program's own target data, so on
     aarch64 it is a different call (`lsetxattr`): measured, `for_over_nonvar` then died SIGSEGV and
     `trunc_guard_bodyless_decls` answered 41. They now pass `std::sysno::MMAP` / `WRITE`; the x86_64
     rows do not move.
   - Predicted transitions: see §3.
2. **2b — one mangling.** Overload sets and operator functions on the twins (#475, #844): the resolved
   callee of every call is decided once (design question in §4, Q3) and printed by `put_fn_symbol` with
   the per-signature suffix; riscv64 and wasm adopt the qualified spelling. Rows: the ASSEMBLE
   `overload_*`, `operator_*`, `issue472_*` paths; #844's wasm wrong value. Deletes the twins'
   `*_callee_defined`, the first-name-match in `*_emit_bl_target`/`rv_emit_call_target`, and wasm's two
   inline copies of the overload suffix.
3. **2c — `call_c`.** `@extern` imports through the AAPCS64 / RISC-V psABI scalar classes on the
   register twins. wasm keeps `unknown import` (D4, §4).

## 3. 2a — predicted manifest transitions (stated before the gate)

Measured on the gate machine with the 2a compiler, emit → assemble → link → run of every path whose
committed aarch64/riscv64 row is `link` (128 paths, 256 rows):

- **121 paths × 2 twins: `link` → `run` 133** (a located `brk`/`ebreak` the program now reaches; the
  first site of each is a legacy-emitter family a later slice owns — 60 "undefined/builtin callee",
  25 "unsupported addr-of", 10 `StructLit`, 6 `StrLit`, 5 sub-word deref-store, …). The x86_64 rows of
  the paths `checked_overflow`, `checked_routed_div_zero`, `checked_routed_narrow` are traps too, so
  those three now AGREE.
- **4 paths × 2: `link` → `run` agreeing with x86_64**: `library_dce_scope/package.al` and
  `library_dce_scope/src/main.al` (0), `trunc_guard_bodyless_decls`, `unchecked_routed_add` (42).
- **3 paths × 2 stay `link`** (other causes): `ambient_io` (`.Lstr35`), and the two package roots with
  no `main` (slice 0b's package roots).
- No x86_64 row moves; wasm rows move only where the gate shows it, and each is listed in the PR.

The exact joined set is the gate's `corpus_manifest.sh --check` output, attached to the PR.

## 4. Open questions (owner / spec)

- **Q1 (D3 on wasm, spec-silent).** A wasm module has no syscall instruction. Options: (a) WASI
  imports for the calls the library needs (`fd_write`, `memory.grow` for an anonymous `mmap`), chosen by
  the library like any per-target row; (b) a located compile-time refusal of `@abi(syscall)` on wasm;
  (c) today's behaviour (a `std::sysno` name with no wasm row, or the call, traps at run time). Slice 2
  keeps (c) and does not choose.
- **Q2 (D4 on wasm, spec-silent).** A bodyless `@extern` on wasm: import from `env` and let the
  embedder fail (today, LOUD-EXIT) or a located refusal. Kept as today.
- **Q3 (2b, design).** Who resolves an overloaded call. Sema does not resolve overloads today (it
  checks a set tolerantly); x86's resolver infers argument types from the expression's shape
  (`lower::overload_args_match`), which D6 forbids for the IR. Proposal: sema resolves the overload
  set from the argument types it already computes and records the chosen declaration per call node
  (records only, verdict unchanged); the twins' front half rewrites the call to that declaration's
  name span. Needs a decision before 2b.
