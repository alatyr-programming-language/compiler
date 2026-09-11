# Changelog

What a *user of the toolchain* would notice. The full record of how the compiler got here is its git
history and `seed/VERSION`; this file is the short version, aimed at someone deciding whether a new
build changes anything for them.

## Versioning policy

The compiler is versioned independently of the specification, and it **cites** the spec revision it
conforms to. Those two numbers move for different reasons and must not be conflated: a spec revision
can land without any compiler change, and the compiler changes constantly without the language
moving at all.

- **MAJOR** — a program **the specification calls valid** no longer compiles, or produces a different
  result. Also: the spec revision this build conforms to moves by a major. The qualifier is doing real
  work: this compiler has accepted many programs the specification declares invalid, and refusing one
  of those is a defect fixed, not a break — see PATCH.
- **MINOR** — new surface: a construct that used to be rejected now works, a backend gains a shape,
  a CLI verb or flag appears.
- **PATCH** — a defect fixed with no new surface, or a diagnostic improved. A **silent wrong value**
  turned into a correct one, or into a loud failure, is a PATCH even though its effect on a program
  can be dramatic; that is the class this project treats as most urgent. **Newly rejecting a program
  the specification declares invalid** is also a PATCH: the defect was accepting it, and someone whose
  code stops compiling for that reason was relying on a bug. Say so in the entry, so the reader can
  tell this case from a break.

Two things that deliberately do **not** move the version: making an existing rejection *louder* or
better-located (the program was already refused), and any change under `scripts/` — the gates are
how this repository proves itself, not part of what it ships.

## When the version moves, and the tag that records it

**The version moves on a seed promotion, and only on one.** `package.al`'s `version` field is the
compiler's identity; a promotion replaces `seed/alatyr` with a materially different compiler, and two
promoted builds reporting the same number is exactly what a version exists to prevent. Between
promotions the number stands still and `## Unreleased` accumulates, so the number identifies a seed
generation together with the tree that seed reproduces — not an individual commit.

`scripts/fixpoint.sh` enforces the pairing: `package.al`'s `version` must equal
`current-seed-version` in `seed/VERSION`'s CURRENT SEED block. It fires on a disagreement in either
direction — a promotion that forgets the bump, and a `package.al` bump made on its own — before it
builds anything. The fixpoint itself would not catch either: the version IS part of the emission (a
compile-time constant, TOOL-21), but changing it moves the seed's output and Stage1's identically, so
they stay byte-equal. What that check does **not** see is a tree where both fields agree and the seed
answers a third thing; that is the state `main` is in today, and #586 is that hole.

**The bump comes first, before the stages are built.** `src/cli.al`'s `cli_version` answers
`app.version`, which TOOL-15 injects as a compile-time constant, so a compiler reports the version of
the tree it was **compiled from** — not the tree it is committed into. Bump, then build, then
promote, and the frozen Stage2 answers the number it is released under. Bumping inside the promotion
commit freezes a Stage2 compiled from the previous tree, and that seed answers the previous version
for the rest of its life: `seed/alatyr` on `main` is recorded, released and tagged `v0.2.0`, answers
`alatyr 0.1.0`, and contains not one occurrence of the string `0.2.0` — where the Stage1 it builds
from that same tree contains 35, one for each embedded copy of the version constant.

The order is fixpoint-safe, measured on a throwaway worktree rather than argued: `package.al` and
`current-seed-version` at a test `0.2.1` over the untouched 0.1.0-answering seed still gave
`seed == Stage1 == Stage2` at 1 224 447 GAS lines, with Stage1 and Stage2 byte-identical and both
answering `alatyr 0.2.1`. The version constant is 35 embedded copies of the string, one differing
byte each; the fixpoint compares two compilations of the same tree, so those 35 bytes move in both
emissions at once — which is why the fixpoint cannot police the version and the seed-identity check
has to.

A promotion therefore happens in this order, and the gate is red if any step is missing.

**Before the stages are built:**

1. `package.al` — the new `version`.
2. `seed/VERSION` — `current-seed-version` moves to that number, in the same step. Not later:
   `scripts/fixpoint.sh` compares it to `package.al` before it builds anything and exits 6 on a
   disagreement, so a bump on its own cannot reach a build at all.
3. `scripts/package_cli_test.sh` — its expected `alatyr <version>` line. This is the one that gets
   forgotten. It hardcodes the `--version` output of a **stage**, so it goes stale the moment
   `package.al` moves and fails the gate with a diagnostic that never mentions the version.

**Then Stage1 → Stage2 → Stage3 are built from that tree** and validated as `AGENTS.md`'s
Reproducibility section and `.agents/skills/alatyr-integrate/SKILL.md` §3 require.

**Then the promotion itself:**

4. `seed/alatyr` — the promoted Stage2 binary, which now answers the new version.
5. `seed/VERSION` — `current-seed-sha256` moves to the promoted digest, and the entry with the three
   stage hashes and the **read** delta is appended. The entry is the reviewable part: it lands in the
   promotion PR, where a human can read the delta before it becomes history.
6. This file — `## Unreleased` becomes `## <version> — <date>`, and a fresh empty `## Unreleased`
   opens above it.

All six land in **one commit**. Between step 1 and step 4 the working copy carries a version the
committed seed does not answer, and `seed/VERSION`'s two CURRENT SEED lines describe two different
compilers for a moment — the digest the old one, the version the one about to be frozen. That split
exists only in the working copy, and the atomicity of the commit is currently the only thing keeping
it out of a published tree: the measurement above passed the complete seed-identity check with both
fields at `0.2.1` over a seed answering `0.1.0`, because only the digest side of that block is
checked against the artifact. Do not commit the intermediate state, and do not "fix" it by moving the
bump back into the promotion commit.

**The tag.** After the promotion lands, an **annotated** tag `v<version>` goes on the promotion commit.
It is created after the merge, so nothing reviews its message — which is why the tag carries the digest
and never the primary record:

```
git tag -a v0.2.0 <promotion commit> -F - <<'EOF'
alatyr 0.2.0

<one paragraph: what this generation of the compiler does that the previous one did not>

Stage1 == Stage2 == Stage3, GAS <n> lines
GAS SHA-256:    <hash>
binary SHA-256: <hash>
Promoted stage: Stage2
Gate: e2e <n>/<n>, corpus <n>/<n>, formatter clean, idiom new=0, sweeps clean
Spec revision: <revision this build conforms to>
EOF
```

The full delta audit stays in `seed/VERSION`. A tag is not in the input tree — a source tarball loses
it, and a tag can be moved with a force-push — so it is navigation, not the record.

Two numbers that are **not** the compiler's version: the specification revision (this build cites it,
`README.md` carries the badge) and the seed lineage in `seed/VERSION`. The specification's own `v1.0.0`
tag lives in the sibling repository; a `v1.0.0` here would mean something else entirely.

## Unreleased
- **A `ptr(T)` annotation's pointee no longer depends on which file name the type is declared in.**
  Exhaustiveness was already independent of module order for a direct annotation (`c : C`), but the
  spelling a real `Expr` walk writes is `e : ptr(C)`, and the pointee of a pointer annotation was
  still resolved against the modules checked *so far*. A `ptr(C)` parameter written in a module that
  sorts before the module declaring `C` therefore recorded "pointer to something unknown", and a
  non-exhaustive `match deref(c)` on it compiled clean — where the byte-identical program with the
  enum's file renamed to sort first was refused. **Newly rejected:** a non-exhaustive `match` over a
  `deref` of such a pointer, with the same located `type mismatch` the earlier-sorting order already
  produced. Nothing else changes: only an *enum* pointee is recovered this way, and only where the
  prefix left it unknown, so pointer-vs-pointer argument compatibility is unaffected. Concretely, in
  this compiler's own source `src/aarch64.al` is the one module sorting before `src/ast.al`, and 39
  of its 63 `_ =>` wildcard arms were unchecked for this reason.

- **A sibling brand can no longer be laundered through an enum variant's payload.** A brand has a
  distinct nominal identity and every brand conversion is explicit (Types §4.2/§4.3); two *sibling*
  brands over one block do not convert into each other at all (§5.4). `E := enum { One(A) }` with
  `E.One(b)` for a `b : B` compiled clean and ran, so a variant payload was the remaining way past
  the annotated binding, the call argument, the struct-literal field, the field store and the field
  read that are already refused. **Newly rejected:** an implicit brand crossing at the payload of an
  **arity-1** enum variant, in either direction (a sibling or cross-domain brand into a branded
  component, and a brand into a raw one). The explicit spellings are unchanged and still accepted:
  `E.One(A(u64(b)))` and `E.One(A(1))`, as are a literal payload (`E.One(7)`, which Types §9.1/§9.2
  refine from context) and a nullary variant. One located `alatyr: check: implicit brand
  conversion …` on all four surfaces — `build`, `check` and the WAT/AArch64/RISC-V emit paths.
  A variant of **two or more** components is unaffected and still accepts the crossing: the AST
  records one payload type span per variant — the first component's — so components 2..n have no
  declared type to judge against. That residual stays open on #299.

- **An array literal can no longer launder a brand through its elements.** A brand has a distinct
  nominal identity and every brand conversion is explicit (Types §4.2/§4.3); two *sibling* brands
  over one block do not convert into each other at all (§5.4). Every sink refused so far judged one
  whole value against one declared type, and an array annotation has neither: the resolver answered
  "this is an array" for `[2]A` and stopped, so `xs : [2]A = [b, b]` compiled clean and read back
  the sibling `b` — the standing way to move a brand into an `A`-typed slot. **Newly rejected:** an
  implicit brand crossing at any ELEMENT of an array literal written at a fixed-array sink, in both
  annotation spellings (`[2]A` and `[A; 2]`), sibling, cross-domain, and in both directions between
  a brand and its raw base (`xs : [2]A = [r, r]`, `ys : [2]u64 = [a, a]`). The `[e; n]` fill form is
  judged the same way. The verdict is one located `alatyr: check: implicit brand conversion …` on
  all four surfaces — `build`, `check`, and the WAT/AArch64/RISC-V emit paths — and it names the
  offending element's own line. The explicit spelling is unchanged and still accepted:
  `xs : [2]A = [A(u64(b)), A(u64(b))]`. Integer-literal elements (`xs : [2]A = [1, 2]`) are *not*
  refused — §9.1/§9.2 give a literal its type from context — and neither are same-brand elements,
  arrays of raw types, or Types §8.1 `@require` contracts. An element of a *nested* array
  annotation (`[[2]A; 2]`) remains open.
- **A raw-asm operand the compiler cannot spell is refused instead of becoming `$0`.** Spec ch.80
  §2/§6 gives a raw-asm instruction operand as a register name or an immediate literal. Anything else
  — `movq(rbx, 0 - 1)`, `movq(rbx, 1 + 1)`, `movq(rbx, unchecked 2)`, `movq(rbx, x)` for a local `x`,
  and the same operands inside an `asm("…{i}…", op…)` template — used to fall through to the
  immediate path and emit `$0`, with rc 0 from both `check` and `build` and nothing printed. The
  program then ran with zero in that register: `movq(rdi, 40)` + `movq(rbx, 0 - 1)` + `addq(rdi, rbx)`
  exited **40** where 39 was due. **Newly rejected:** a raw-asm source operand that is neither a
  register name nor an integer/boolean literal, with one located build diagnostic naming the
  instruction and the operand's argument position. The admitted forms are unchanged and still
  compile: `-1` (the parser folds it to a single literal), a bare decimal, `true`, a register, and a
  template immediate. This is not a constant fold — whether a constant-*foldable* operand should be
  accepted is a language question for the specification and is not answered here.

- **A module-level value declaration no longer launders a brand.** A brand has a distinct nominal
  identity and every brand conversion is explicit (Types §4.2/§4.3); two *sibling* brands over one
  block do not convert into each other at all (§5.4). Every sink the refusal reached so far was
  inside a function body, because a module binding carries no dedicated type field and is not one of
  the checker's statement-level value sinks — its `: T` is recovered from the source at the
  declaration itself. So `G : A = B(1)` at module scope compiled clean and ran, and it was the last
  unhooked way to put a sibling brand into a brand-typed binding. **Newly rejected:** an implicit
  brand crossing at an annotated module-level declaration, in every direction — a sibling
  (`G : A = B(1)`), a brand over another block (`G : A = C(3)`), a raw value into a brand
  (`G : A = u64(3)`), a brand into a raw slot (`H : u64 = A(1)`), a `mut` binding, and an
  initializer whose type comes from a declared callee result (`G : A = mk()`). The diagnostic is the
  usual located `implicit brand conversion` on all four surfaces. The legal spellings are unchanged:
  a same-brand initializer, the explicit route through the shared block (`G : A = A(u64(b))`), an
  explicit removal (`GR : u64 = u64(A(7))`), and an integer literal taking its type from the
  annotation (`GL : A = 5`, Types §9.1/§9.2 — not a conversion, and deliberately untouched). This
  also closes the **composition** of this sink with the array-literal one: a module-level
  declaration annotated with an array (`G : [2]A = [B(1), B(2)]`) is now refused per element, a
  shape neither slice covered on its own. A MULTI-COMPONENT enum-variant payload remains open
  on #299.
- **A nested submodule of your package is type-checked now — it was not type-checked at all.** The
  compiler decided which modules to TRUST by looking for `__` in the *mangled* module name, which is
  how it spells a path separator: `src/geo/child.al` becomes `geo__child`, the same shape as the
  ambient stdlib's `std__io`, so every nested submodule of every package was skipped wholesale by
  both `check` and `build`. A name declared nowhere compiled there, linked, and ran: measured on a
  two-module package, `check` rc 0, `build` rc 0, an executable produced, and the unbound name
  lowered to `movq -8(%rbp), %rax` — an uninitialized frame slot returned as the program's result.
  **Newly rejected:** anything in a nested submodule that the checker already refuses in a top-level
  one — an unbound name, a type mismatch, a non-exhaustive `match` on a known enum, a private
  cross-module reference, a `[T]` in a signature. The verdict is the ordinary located
  `alatyr: check: … at line N in <module>`, identical on `check` and `build`. Which modules are
  libraries is now answered by where the file came from — the ambient `<install>/lib/` tree and
  resolved path dependencies — instead of by how its name happens to be spelled; the ambient stdlib
  is trusted exactly as before, and a `lib/` directory inside your own `source_dir` is your code and
  stays checked. This was the compiler's own blind spot too: `src/lower/*.al`, twelve files and
  12 007 lines of it, had never been type-checked, and enabling the checker there found four
  declarations it refuses — all four addressed in the same change.

## 0.2.2 — 2026-09-10
- **A `::` head that names nothing is now a compile error instead of a silently different call.**
  `zzz::aa()`, with no `zzz` declared anywhere, used to build at rc 0 and run the *root's own* `aa`:
  every resolver in the tree matches a qualified callee by its trailing segment alone, so the head
  was never read. That is a wrong answer to a typo — you name one thing and get another, with no
  diagnostic. **Newly rejected:** a call whose `::` head names none of a module (by path), a type
  used as an associated-function or variant namespace, a local alias to either, one `pub` re-export
  projection, or an intrinsic namespace (`atomic`, `volatile`). The verdict is one located
  `alatyr: check: no module, type, or alias named ...` on all four surfaces — `build`, `check`, and
  the WAT/AArch64/RISC-V emit paths — and it is reported at the *end* of the check, so it never
  depends on the order the modules were listed in. An `@extern` import (Modules §7) is an ordinary
  declaration and is not affected; neither is FFI. One consequence worth naming: for a manifest-less
  `alatyr build a.al b.al`, the first file is the package root and Tooling §4 excludes it from
  module-path scanning, so `a::something()` from `b.al` names nothing and is now refused too.

- **Two more ways to launder a brand through a struct field are refused.** A brand has a distinct
  nominal identity and every brand conversion is explicit (Types §4.2/§4.3); two *sibling* brands
  over one block do not convert into each other at all (§5.4). The refusal that landed earlier
  reached the annotated binding, the `=` re-assignment of a name, the call argument, the declared
  result, the early `return`, the binary operator, the struct-*literal* field and the brand
  constructor — but not a write into an already-built struct, and not a value read back out of one.
  So `s.x = b` compiled clean and ran, which made it the standing way around all of the above, and
  `fld : u64 = s.x` dropped the field's brand on the way out. **Newly rejected:** an implicit brand
  crossing at a struct-field store (`s.x = b`, sibling or cross-domain — a *raw* value there was
  already refused as a type mismatch) and at any sink fed by a direct branded field read
  (`fld : u64 = s.x`, `b : B = s.x`, `take_a(s.y)`, `a + s.y`). The explicit spellings are unchanged
  and still accepted: `s.x = A(u64(b))` and `u64(s.x)`. Same-brand stores and reads, widening, and
  Types §8.1 `@require` contracts are untouched. Nested place paths (`s.t.y = b`) and a field read
  through an index or pointer root remain open.
- **On aarch64, riscv64 and WASM, an `i64` local declared inside a block — and a local inferred from
  arithmetic over one — is now signed for arithmetic too, not just for its comparison.** Those three
  backends have no slot map to read a local's type from; they recover it by scanning the source, and
  the scan walked only the function body's TOP-LEVEL statement list. Two shapes therefore never
  resolved and both fell to the UNSIGNED default. `mut m : i64 = neg()` written inside an
  `if`/`while`/`loop`/`match` arm took the unsigned carry guard on `m + 1` while `m < hi` beside it
  kept the signed comparison, and at `m = -1` the two disagreed and the program died on the guard's
  trap. `d := m - 1` records no annotation at all, so `0 + d + p` trapped the same way — and `d / 2`,
  `d % 4` and `shr(d, 1)`, which select an instruction rather than a guard, ran to completion and
  returned the UNSIGNED answer: a clean build, a normal exit, a wrong number. Types §3.2 puts
  signedness in the operations — the operand's interpretation picks the intrinsic exactly as it does
  for `+` and `<` — and Concurrency §6.1 traps only an operation that overflows, which `-1 + 1` does
  not for `i64`. The scan now descends into every nested block for a native-width SIGNED annotation,
  and an un-annotated local bound from an arithmetic expression takes its operands' signedness when
  they prove it. Both refusals of the x86 repair above are inherited verbatim: a NARROW annotation
  is not adopted (it carries the §4 value model, recovered by a separate scan that is still flat),
  and a native UNSIGNED one is not either — that direction is #546's question. All four backends now
  agree on both shapes; x86_64's answer, which was already right, does not move a single emitted
  byte.
- **A signed local whose name is also bound, untyped, somewhere else in the same function no longer
  crashes the compiler's output on `k + 1`.** `:=` locals are function-scoped in this backend and
  the slot binder no-ops on a name it has already bound, so of two declarations of one name only the
  first reached the slot map — with the first binding's recorded type. When that first one was
  untyped (`mut k := 0`), a later `mut k : i64 = ...` lost its annotation, the signedness scan could
  not prove the counter signed, and its `+` took the UNSIGNED carry guard while `k < hi` beside it
  kept the SIGNED comparison. At `k = -1` the two disagreed — the compare read -1 and continued, the
  increment carried, and the program died on the guard's `ud2` with no diagnostic. Types §3.2 puts
  signedness in the operations, so the operand's own interpretation picks the add and the compare
  alike, and Concurrency §6.1 traps only an operation that OVERFLOWS: `-1 + 1` does not overflow
  `i64`. A rebinding whose annotation is a native-width SIGNED integer now fills a slot entry that
  recorded no type at all; a first binding's type is never overwritten, a narrow annotation is not
  adopted (it carries the §4 value model, which must not apply retroactively to the earlier scope),
  and a native UNSIGNED one is not adopted either — that direction would move a comparison off the
  signed default, which is #546's question and not this one. This is what removed the three
  `unchecked` bypasses 0.2.1 had to put on the `comptime for` unroll counters in the aarch64,
  riscv64 and WASM emitters: those three loops are the shape, and their compilers were dying on it.

## 0.2.1 — 2026-09-10

- **A written negative integer literal is now one literal, and the three silent wrong values that
  followed from it are gone.** The parser represented every unary minus as an `unchecked`
  subtraction from zero, so fifteen compiler predicates that ask "is this a numeric literal"
  answered *no* about `-129`. Three consequences, all of them silent: a literal below a signed
  type's lower bound was accepted and wrapped (`n : i8 = -129` and `i8(-129)` both ran to 127 on
  all four backends, where Types §9.1 requires a compile error); `mut G := -9` materialized 0 in
  `.data` on x86_64 and wasm and trapped on aarch64 and riscv64, while the same value written
  `0 - 9` was correct; and `comptime for i in -2..2` unrolled two iterations instead of four.
  `-<digits>` written with nothing between the minus and the digits is now a single literal
  carrying the negative value, and all three are fixed. **Newly rejected:** a negative literal
  outside its target type's range, in the annotation, constructor, module-binding, argument and
  `return` positions — including `n : u8 = -1`, since no negative value is representable in an
  unsigned type. `unchecked` still wraps, `-128`, `-32768`, `-2147483648` and `i64`'s minimum stay
  accepted, `-0` is the mathematical zero everywhere, and a negation whose operand is *not* a
  literal (`-v`, `- (5)`, `- -4`) is unchanged in both shape and value.
- **A range slice indexed directly, `xs[lo..hi][i]`, now reads the view's element on aarch64,
  riscv64 and WASM too.** Grammar §3.4 writes `postfix-expr ::= primary { postfix }` with both
  `"[" expr "]"` and the range form among the postfix ops, so this is one primary and two postfix
  steps and needs no intermediate binding — yet `v := xs[lo..hi]; v[i]`, the same access one
  binding later, was the only spelling those three backends lowered. Every arm of their index
  chains keys on a bare name, so a slice base matched none of them and the shape reached their
  fail-loud default: a program that compiled cleanly and then trapped. All three now compose the
  element address off the {ptr, len} their own slice-binding path already stores, bounds-checked
  against the view's runtime length, so the two spellings name the same byte. x86_64 (unchanged
  here) closed its half earlier. An index past the view's end still traps rather than reading the
  base array beyond `hi`, and `unchecked` still drops that check. Float-element, `[u8; N]`-packed,
  struct-element, array-parameter and array-global bases keep their existing fail-loud behaviour.
- **An element store through a nested field path is no longer discarded.** `outer.leaf.arr[i] = v`
  and deeper paths matched no assignment statement form — the recognizers demanded the `[`
  immediately after the FIRST field — so the line fell to the trailing-expression path and the store
  was emitted on none of the four backends, with exit 0 and no diagnostic; the write-permission and
  element-type rules never ran either. The parser now recognizes a field path of two or more owners
  ending in an indexed write and records the ordinary `IndexAssign` every backend already lowers.
  The single-owner `v.field[i] =` form keeps its existing path unchanged. Stores through an
  immutable owner are now refused with a located diagnostic.
- **A narrow signed `MIN / -1` now traps instead of answering an unrepresentable value.**
  `MIN / -1` is a member of the checked-overflow set at every signed width, but each backend's
  guard compared the dividend against the 64-bit `INT64_MIN` alone — a bound a narrow dividend can
  never reach. `(-128 : i8) / (-1 : i8)` therefore produced 128, a value outside `i8` living in an
  `i8` binding, identically on x86_64, aarch64, riscv64 and wasm. The guard now materializes the
  operand's own minimum (-128 / -32768 / -2147483648) and takes the family's direct inline trap.
  Native-width division emits exactly the bytes it did before, `%` is untouched (`MIN % -1` is 0 and
  representable), and `unchecked` keeps its target-specific hardware behaviour. Unary `-` on a
  minimum value still wraps silently at every width and is tracked separately.
- **Pointers inferred from a local address now retain the local's declared struct identity.**
  The bootstrap type carrier could erase both the `ptr` tag and its pointee name for
  `p := ptr(mut value)`, so a later `deref(p).inner.f = "text"` bypassed the leaf's
  `u64` compatibility check. Dedicated AST accessors now recover only the invariant pointer
  tag and a proven local-struct pointee; unsupported address expressions remain unknown.
  Correct deep integer and boolean stores continue to return 42.
- **Assignment type checking now follows every declared field in a pointer-rooted place.**
  A direct `deref(p).f` store was checked, but `deref(p).inner.f = "text"` still accepted
  a string at a `u64` leaf. The semantic check now mirrors the recursive field-place grammar
  from a proven `ptr([mut] Struct)` pointee and rejects the mismatch before lowering. Unknown
  pointees, indexes and slices remain poison-tolerant; correct integer and boolean stores still
  return 42.
- **Assignment type checking now follows a direct pointer-returning call into its field place.**
  The explicitly typed local form was checked, but `deref(make_ptr()).f = "text"` still accepted
  a string at a `u64` field. A uniquely resolved direct call's declared `ptr([mut] Struct)`
  result now feeds the same field-type compatibility check; indirect, ambiguous, unknown-pointee,
  and deeper pointer expressions retain their existing boundary. Correct integer and boolean
  stores through the call-produced pointer continue to return 42.
- **A wrong-typed value can no longer be stored through a field reached by an explicitly typed
  pointer.** Types §4.2/§4.3 and Memory §3.2 make assignment a typed value-to-place store, but
  `p : ptr(mut P) = ptr(s); deref(p).f = "text"` accepted a string at a `u64` field and stored
  its address. The semantic place check now resolves the declared pointee struct and field type,
  rejects the mismatch at the field with the existing diagnostic, and preserves correct integer
  and boolean stores. Inferred or unknown pointees and deeper pointer-derived paths remain separate
  residuals of #304.
- **A `bitcast` now decides a relational operator's signedness, so `bitcast(i64, x) < 0` is no longer
  constant-false and a guard written that way actually refuses.** Types §4.2 makes `bitcast` the
  reinterpret conversion — the same bits, with the target `T` deciding how they are read — and a
  relational operator is exactly the construct that reads it. The compiler consulted the operand's
  *declared* type instead: `unchecked bitcast(i64, off) < 0` over a `usize` `off` was lowered
  UNSIGNED and answered **false for every value of `off`**, identically on x86_64, aarch64, riscv64
  and wasm. That is not a wrong boolean, it is a silenced guard: every refusal predicate of the form
  "if this went negative, refuse" compiled to "never refuse", from a clean build with a normal exit.
  The cause was structural rather than a missed case — `src/parser.al` identity-erases a word-sized
  bare scalar `bitcast` target, so no `Expr::Bitcast` node reaches the four signedness predicates at
  all and there was nothing there for them to look through. The written target is now recovered from
  the source around the operand, once, in `lower_layout`, and all four backends ask their own
  unchanged unsignedness question about the result. The mirror direction works too: a `u64` target
  forces the unsigned reading where the declared type would have proven signed. Nothing else moves —
  a genuinely unsigned comparison across 2^63 keeps the unsigned condition, a `u64` target keeps it
  rather than acquiring a signed one, and emission over `src/` + `lib/` is byte-identical (#546).

- **A parameter, a local or a `comptime` binding named like a module constant now wins on x86_64
  too.** Declarations §5 makes scope lexical and block-structured and a function — its parameters and
  its body — an inner scope of the module, and §6.1 gives the inner name the win for the extent of
  that scope. On x86_64 it did not: the assignment lowering resolved a right-hand-side name to a
  module constant's value on the NAME alone, before it asked anything else about the statement, so
  `K := 3` at module level with `f := fn(K : f64)` called with 41.5 stored **3** — a clean compile,
  exit 0, no diagnostic. aarch64, riscv64 and wasm already answered the shadowing binding, so this is
  the rarer and more dangerous arrangement: the wrong column was the one the cross-target sweeps
  compare everything else against, which is why nothing caught it until a fix on the other three
  backends needed a shadow guard to avoid reproducing it. All four backends now answer the inner
  binding, for an annotated local, an unannotated bind and a `comptime` binding, from either a
  parameter or a local home. Declarations §7.2 is preserved in both directions: a declaration's own
  initializer (`K : u64 = K`) and a read placed before a later local of that name still mean the
  constant, because the guard asks about bindings declared BEFORE the statement rather than anywhere
  in the function. Nothing else moves — an unshadowed constant still resolves, including the float
  arrival the previous release had just made agree across backends, and all 8 076 tracked
  (fixture x backend) artifacts are byte-identical. A shadowed `str`, struct, array or enum constant
  is deliberately untouched and stays as it is today (#598), as is a shadowed const-STRUCT-FIELD
  base, which answers the constant on all four backends rather than only on x86_64 (#597).
- **An integer literal that does not fit its target type is now refused through the conversion
  constructor `T(v)` too, not only through an annotation.** Types §9.1 makes an integer literal's
  type "inferred from context" and its representability in that type "checked at compile time — a
  literal outside the target type's range is a compile error (I11), never a silent wrap", and §9.2
  names `T(v)` as one of the two forms that *refine* a literal's type. Only the annotation form was
  checked: `n : u8 = 300` was refused, while `n : u8 = u8(300)`, `n := u8(300)` and `N(300)` for
  `N := brand(u8)` compiled clean on all four backends and **ran to 44** — the literal wrapped into
  the byte — and `N(1000)` ran to 232. Refused now wherever the constructor is written: a binding
  with or without an annotation, a module-level binding, a `return` or tail value, a call argument, a
  struct-literal field, an array element, an operand of an operator, and nested inside another
  constructor; the diagnostic is the same located `type mismatch` the annotation form already gave.
  **This newly rejects programs the specification declares invalid**, so by this file's versioning
  policy it is a defect fixed and not a break, and the spelling that keeps the old behaviour is the
  one §4.2 already prescribes: `unchecked u8(300)` still truncates (CG-7). Three things are
  deliberately untouched: a representable literal (`u8(255)`, `i8(-1)`, and the largest `u64`), a
  **non-literal** operand — `u8(x)` for a run-time `x` is §4.2's checked-narrow case, whose value is
  not a compile-time fact and which still truncates — and the neighbouring constructors `char(n)`
  (whose own §8.1 `@convert` guard is a separate gap) and `f64(n)`. A written NEGATIVE literal below a
  signed type's bound (`i8(-129)`, and `n : i8 = -129` alike) is still accepted and still wraps: the
  parser represents it as an `unchecked` subtraction rather than a literal, so both spellings share
  that hole and neither path is worse than the other. Emission is unchanged for every program that
  still compiles: this is a `check`-stage rule, and all 2 019 pre-existing tracked fixtures produce
  byte-identical exit statuses, byte-identical diagnostics and byte-identical GAS. Three of them had
  to be rewritten first, and that is worth stating plainly: `conv_narrow`, `conv_signed` and
  `int_narrow_conv` are §8 backend-breadth rows that asserted **42** for `u8(810)`, `i8(200) + 98`,
  `u16(70000)` and `u32(4294967338)` — the silent wrap itself, frozen into the corpus oracle as
  expected behaviour. Their subject (that a narrowing conversion exists and wraps on every backend) is
  legitimate and is preserved exactly: each operand is now a value in the next wider type
  (`u8(u16(810))`, `i8(u8(200))`), every literal is representable in its own target type, the emitted
  narrowing instruction is unchanged (one movzbq/uxtb/andi/i64.and; three movsbq/sxtb/slli+srai and one
  i64.extend8_s), and all three still run to 42 on all four backends. The refused spellings are not
  lost: they become `reject_conv_narrow_literal`, `reject_conv_signed_literal` and
  `reject_int_narrow_conv_literal`, each asserted on the build path and the three emit-to-stdout
  surfaces.

- **A `brand` now carries the identity Types §5.4 gives it: a sibling brand, the raw type it brands
  and a brand over another block no longer convert into it implicitly.** §5.4 makes branding "the
  primitive that grants a distinct nominal identity over a shared layout", §4.2 classes every brand
  crossing as the constructor form `T(v)`, "always explicit", §4.3 makes **widen** the only implicit
  conversion class, and §5.4 adds that two *sibling* brands over one block do not convert into each
  other at all — "Sibling interpretations are not each other's underlying type; only the block they
  share is." The compiler enforced none of it: `Meters` and `Seconds` were interchangeable, a bare
  `u64` passed for either, and even a `brand(u8)` was accepted where a `brand(u64)` was declared.
  Refused now at every value sink the checker reaches — an annotated binding, a `=` re-assignment, a
  direct or UFCS call argument, a declared result, an early `return`, a binary operator (an
  `if`-expression's condition included), a struct-literal field, and a brand constructor handed
  another brand — with a diagnostic of its own that names the remedy: write `A(v)` / `u64(a)`, or for
  a sibling route through the shared block as `A(u64(b))`. **This newly rejects programs the
  specification declares invalid**, so by this file's versioning policy it is a defect fixed and not a
  break; code that stops compiling was relying on the check being absent, and the explicit spelling
  it needs exists for every class. Nothing else moves: widen stays implicit, the same brand stays
  self-consistent, a Types §8.1 `@require(pred) U` validity contract keeps its own (currently
  unenforced) identity rather than acquiring brand rules, and an integer literal meeting its own brand
  annotation is untouched — §9.1/§9.2 make an annotation one of the two forms that *give* a literal
  its type. Emission is unchanged for every program that still compiles: this is a `check`-stage rule,
  and all 2 014 tracked fixtures produce byte-identical diagnostics and byte-identical GAS. Five
  sinks are still not reached — a module-level value declaration, an array-literal element, an
  enum-variant payload, a struct-field store, and the brand-to-raw direction through a field read —
  and `test/accept_brand_unrefused_sinks.al` records each with its reason so the gap cannot be
  mistaken for coverage.

- **A non-`pub` declaration is now refused for its BARE spelling too, not only its qualified one.**
  Modules §3 line 73 defines visibility as who may *name* a declaration, and lines 80-85/90-92 put an
  unrelated module outside a non-`pub` declaration in every spelling; the compiler applied the test
  only in the qualified arm of its resolver, so one declaration answered two different ways depending
  on nothing but how the caller wrote its name. Measured: from an external package,
  `base::str::char_byte(cur, 0)` was refused while bare `char_byte(cur, 0)` built and ran. Three
  spellings are affected — a bare CALL, a bare TYPE head, and a private function used as a VALUE
  (`f := secret; f()`), which had no visibility test at all. Everything §3 makes legal is unchanged: a
  `pub` name stays reachable bare (Stdlib §1 injects the base prelude unqualified), a module still
  names its own private helpers, a descendant still names its ancestors' (§3:80-85), and a name a
  parse-time desugar synthesized — `@alloc`'s `alloc_into`, `defer`, the cloned `__hoflam` closure —
  is exempt, because nobody named it. Emission is unchanged: this is a `check`-stage rule, and a
  program that compiled before compiles to the same bytes.

- **A non-exhaustive `match` is now refused whatever the scrutinee looks like, and whatever order a
  package's modules sort in.** Control Flow §5.1 requires every `match` to cover every variant or
  carry a `_` default, and calls a non-exhaustive one a compile error. The compiler enforced that for
  exactly ONE scrutinee spelling — a bare identifier naming a local whose annotated type resolved to
  an enum — and silently accepted every other. Measured over one three-variant enum with only the
  scrutinee's spelling varied: a by-value parameter and an annotated local were refused, while an
  inferred `c := C.R` binding, `deref(p)` through a `ptr(C)`, a struct field read and a call result
  all compiled. Exhaustiveness is now decided from the scrutinee's TYPE however that type was
  obtained, so all six are refused, with the diagnostic located on the scrutinee. A second, unrelated
  half: the enum-declaration lookup walked only the name-resolution prefix, so the identical
  two-module program was refused when the enum's file sorted first and accepted when it sorted last;
  the verdict no longer depends on a file name. **This newly rejects programs the specification
  declares invalid** — a defect fixed, not a break, in the sense this file's versioning policy spells
  out: code that stops compiling for this reason was relying on the check being absent, and the fix
  is to cover the missing variant or write the `_` the specification already allows. A `match` with a
  `_` default, one that covers every variant, and OR-pattern groups are all accepted exactly as
  before, and where the scrutinee's type genuinely cannot be resolved the check still fails open.
  The compiler's own sources needed four `match deref(e)` sites over `ast::Expr` completed to keep
  building; nothing a user of the toolchain can observe changed about what it emits.

- **In a manifest-less invocation of two or more files, the first listed file is now the package's
  root module instead of a sibling of the others.** Tooling §4 makes that file the synthesized
  package's root and excludes it from module-path scanning, "so it is not also a module by its own
  stem"; the compiler named it by its stem anyway. Two things follow. Its declarations now emit
  **unprefixed** linker symbols (Modules §6.1) — `alatyr build a.al b.al` writes `main` and `aa`
  where it used to write `a__main` and `a__aa`, while the other listed files keep their
  `<stem>__<name>` form. And its stem is no longer a module path: `a::aa` used to select the root's
  own declaration, and used to be refused with the Modules §3 visibility verdict when that
  declaration was not `pub`; it is now treated exactly like a module head that names nothing. The
  artifact base (TOOL-11) is unchanged — still the first file's stem — and a build with a manifest,
  where the root comes from the manifest, is byte-identical. A bare list of a **single** file is not
  yet covered and keeps its stem-named module.

- **`unchecked` in front of an integer constant no longer defeats the integer-to-float conversion.**
  `x : f64 = unchecked 3` compiled cleanly, emitted no diagnostic, and read back `0` on all four
  backends — the integer bits were stored unchanged and reinterpreted as a denormal — while the plain
  `x : f64 = 3` was correct. `unchecked e` is a verification **mode** (Grammar §3.7, CG-7): inside its
  scope the checked-guard family is dropped and, as an expression, it yields the inner value, so it can
  never change the type or the value of what it wraps. The predicate that decides the TYP-13 conversion
  exists in four independent copies, one per backend, and every one of them matched `Expr::Num` and
  `Expr::Bin` only; `Expr::Unchecked` is a distinct node, so all four answered "not an integer
  constant". Each now unwraps it. Covered at both widths, for the bare literal and for a folded
  `+`/`-`/`*` tree, for a negative value and for nested grants. The grant itself is unchanged —
  `unchecked` arithmetic still wraps and un-`unchecked` arithmetic still traps — and emission for every
  other shape is byte-identical, measured by artifact hash over all 1 980 tracked corpus sources on all
  four backends.

- **A module constant or a const-struct field initializing a float local is now converted to the
  floating value on aarch64, riscv64 and wasm too, not only on x86_64.** `K := 3` with
  `a : f64 = K`, and `C := S(k = 3)` with `a : f64 = C.k`, compiled cleanly, emitted no diagnostic and
  answered **3 on x86_64 and 0 on the other three backends** — the integer bits were stored unchanged
  and read back as a denormal. Types §9.1 accepts an integer literal in a floating-point context when
  the value is exactly representable, and a constant the compiler itself resolves to that literal is
  the same initializer, so the four backends must not disagree about its value. The cause was
  structural rather than a missed case: the x86_64 lower normalizes the assignment's right-hand side
  through its module-constant resolver before it asks the conversion question, so its predicate saw an
  already-resolved integer literal, while the three other emitters never had that resolution step at
  all — they were an unmeasured column, not a correct one. All three now resolve exactly the one level
  x86_64 resolves and then ask their own unchanged predicate, so a `mut` global, a deeper field chain,
  an arithmetic tree over a constant, and an integer-annotated local keep the path they already took.
  Covered at both `f32` and `f64`. A name shadowed by a parameter, a local or a match binding is
  deliberately left alone, because there the expression does not denote the constant. Emission for
  every other shape is byte-identical, measured by artifact hash over all 2 014 tracked corpus sources
  on all four backends.

- **`checked_mul` / `overflowing_mul` / `saturating_mul` no longer report overflow for every non-zero
  left operand on a target with no high-half-of-product intrinsic.** The `u64` and `i64` members of
  the overflow-policy family read the product's high word out of `mut hi := a` followed by three
  `comptime if target.arch == Arch.{x86_64,aarch64,riscv64}` arms naming `mulhiq`/`umulh`/`mulhu`
  (and their signed twins). `Arch` names no wasm variant — Manifest §3.2 and Assembly §10 enumerate
  six machines and WASM is an additive backend (FND-6) — so on the wat emitter every arm folds false,
  `hi` kept the value of `a`, and `checked_mul(7, 6)` answered `None`: a clean compile with the wrong
  answer, on the one target where the library was reachable at all. The six bodies now carry a
  portable division-based fall-through under the complementary predicate, so a target that names no
  high-half intrinsic computes the same answer the three intrinsic arms do, including at i64 MIN and
  for the `MIN * -1` product that does not fit. x86_64, aarch64 and riscv64 emission is byte-identical.

- **A field read through `deref(ptr(x))` on a by-reference `in out` struct parameter now answers the
  field instead of `0`.** `deref(ptr(x)).b`, where `x` is an `in out` struct parameter, compiled
  cleanly, emitted no diagnostic and produced a literal zero, so in an arithmetic context the answer
  simply came out short — `40 + deref(ptr(x)).b` returned 40 where 101 was due. The emitter's scalar
  field case reaches a pointee read through five span resolvers that each peel a different inner node
  (a `Var`, a nested `Deref`, a `Call`, a `Field`, an `Index`); `Field(Deref(AddrOf(Var)))` is none of
  them, so no arm claimed the read and it fell through to the placeholder `movq $0, %rax`. Memory §4.3
  makes `ptr(x)` the address of the place `x`, so `deref(ptr(x))` **is** the place `x` and the read is
  the ordinary `x.f`. The `AddrOf` is now peeled and the read routed onto the pointee arm an `ek = 7`
  pointer local already uses, guarded on the single slot shape whose word really is a pointer to the
  caller's struct — a by-reference struct parameter — so it emits the same instruction pair the two
  working neighbours already emit: the direct `x.f` read on that parameter, and `deref(q).f` through a
  `ptr(T)` callee. Both the word tier (all-`u64` fields) and the standard byte tier (mixed `u32`/`u16`/
  `u64` widths, a sized load) are covered. The discriminator was the by-reference parameter root, not
  the `deref(ptr(...))` spelling. The non-x86 backends fail loud on this read and are unchanged
  (aarch64 133, riscv64 133, wasm 134, before and after); with the input tree held fixed in both
  directions the x86_64 emission of the compiler's own build is byte-identical.
- **A qualified call to an overloaded `base::` declaration no longer runs the last-declared overload's
  body on aarch64, riscv64 and wasm.** The three module-unaware backends resolve a `mod::fn` callee
  through `driver::d_qual_target`, which matched by (module, tail NAME) alone and kept the LAST hit.
  `base::num` declares each overflow-policy family eight times, in the order u8 u16 u32 u64 i8 i16 i32
  i64, so every `u64` call bound to the **i64** body: `base::num::checked_sub(1u64, 2u64)` answered
  `Some(-1)` where `None` was due, and `saturating_sub(1u64, 2u64)` answered 18446744073709551615
  where 0 was due — a clean compile, a clean run and a signed answer for an unsigned call. That
  resolution now picks the member whose PARAMETER signature matches the call's arguments, the way
  x86_64's own per-signature machinery already does; an argument's type is read from the enclosing
  function's parameter list or from an annotated local, and an argument whose type cannot be read
  matches any parameter. A callee with one declaration — every callee in `src/` and `lib/` outside
  these families — resolves to the same decl as before, so emission is byte-identical for it, and
  x86_64 never runs this code at all.
  Because both members of one name can now be reached in one program, the wat emitter labels a
  driver-disambiguated overload set by the decl's parameter signature (`$saturating_sub__u64_u64` vs
  `$saturating_sub__i64_i64`), taking the suffix at the definition and at the rewritten call site from
  the SAME `Decl`, so the two cannot drift. aarch64 and riscv64 still label a definition with no
  signature, so such a set keeps dropping the injected closure there and traps LOUD (exit 133) where
  the parent answered wrongly — #475's remaining half. A set reached by a BARE call registers nothing
  and is unchanged: its call site carries no declaration identity to name.

- **An integer-to-pointer `bitcast` now lowers on aarch64 and riscv64 instead of trapping.**
  `bitcast(ptr([mut] T), n)` had no lowering on either backend: every preserved pointer target
  answered with an anonymous fail-loud stub (`brk #0 // unsupported bitcast`,
  `ebreak # unsupported bitcast`), so a program x86_64 runs to completion stopped at a SIGTRAP —
  exit 133 under qemu — on those two. A pointer value is one machine word and Types §4.4 makes a
  bitcast the identity on the bits, so the node lowers to exactly its inner value, which is what the
  x86_64 lower has always emitted. Both preserved pointer shapes are covered: a sub-word pointee
  (`ptr(mut bits8)`, the arena-handle idiom) and a pointer-to-user-type pointee (`ptr(mut Node)`),
  in every spelling the grammar admits — `ptr(u8)`, `ptr( mut u8 )` and `ptr (mut u8)` all take the
  same path. A `deref` LOAD through such a pointer now also moves the pointee width rather than a
  full word, so a one-byte read reads one byte instead of the seven bytes after it. Two shapes stay
  fail-loud and are now **located** rather than anonymous: a `bitcast` to a bare user aggregate name
  (not a single machine word — the stub names the construct and the target type), and a `deref`
  STORE through a sub-word pointer (a narrow store would expose these backends' non-conforming
  `@repr(T)` enum tag image, which is a separate gap). x86_64 and wasm are unchanged; with the input
  tree held fixed the x86_64 emission of the compiler's own build is byte-identical.

- **The base prelude tier is now reachable by its qualified specification spelling from outside a
  package: 203 specification-enumerated declarations in `lib/base/` carry a `pub` marker.** Modules
  §3 lines 90-92 make the `pub` chain to the root the **only** way anything leaves a package — "a
  library's public API is exactly the `pub`-chain-to-root-reachable surface" — and Stdlib §1 / §7.1
  require the base tier to be reachable, unqualified, from any program. The Stdlib appendix §8.6
  makes every definition it lists **required v1 content**. The tree satisfied none of that for the
  base tier: `lib/base/num.al` had 146 declarations and **zero** markers, and across `lib/base/`
  227 declarations were unmarked. So `base::num::wrapping_add(a, 2)`, `base::alloc::arena_over(…)`,
  `base::cmp::eq(…)`, `base::derive::eq(…)`, `base::assert::assert(…)`, `base::process::exit(…)`
  and the `base::u128::u128` operator surface were each refused with a located `check` diagnostic
  for an ordinary user package, and the same operations were reachable in their bare spelling only
  through an unrelated visibility hole. This is a conformance fix, not a new API: the overflow
  family is fixed by rule (appendix §4.3 plus Concurrency §6.3/§8.5 — four policy prefixes over the
  checked-overflow operations over the integer interpretations) and the tree's 96 functions are a
  strict **subset** of what that rule requires, while everything named in a §3.1-§3.6 / §4.2 / §5.1
  / §5.2.1 code block is enumerated literally, one identifier per line.
  Nothing else became reachable. The 21 genuinely internal helpers stay private — `sys_exit_group`,
  `char_byte`, `is_ascii_ws`, `split_byte`, `split_piece`, `sift_down`, `sift_down_by`, `bytes_eq`,
  `slice_eq`, `slice_cmp`, `hash_bytes`, `str_hash`, and the whole `Buf`/`buf_*` set — and so does
  `alloc_into`, because Modules §3 line 73 scopes visibility to who may **name** a declaration and
  no user source names it: the `@alloc(a) x := init` desugar synthesizes that callee span, and the
  appendix defines no `alloc_into` identifier. `to_char` stays private as the unnamed `@convert`
  behind §3.2's `char(n)`.
  **No emitted byte moves.** Visibility is distinct from linker-symbol emission (Modules §3:73-76,
  and §6.4's table makes the `pub`-chain API "not exported" for `kind = executable`). The two
  emission-affecting readers of the `pub` predicate are `library_api_root`, which excludes the
  `base__`/`alloc__`/`std__` tier modules outright, and `mangled_symbol_is_global`, which is
  unconditionally true for an executable and for a library artifact can only mark a tier symbol the
  artifact already contains — and no `base__` symbol reaches the GAS of any library-kind fixture in
  the corpus. The compiler reproduces itself byte-for-byte.

- **A diagnostic whose offending expression came from a parse-time desugar now names the construct
  the programmer wrote, instead of killing the compiler with no output at all.** `defer f(x)`,
  `@alloc(A) x := init` and a capturing higher-order call are rewritten during parsing into calls to
  names no source file contains (`__defer`, `alloc_into`, `__hoflam<fnpos>`), and the span those
  synthesized callees carry is not a source offset: it is the AST-arena address of the written name,
  rebased modularly so that `(src + s)` recovers the **name**, which is the only thing it is for.
  Every consumer that instead read `s` as a **position inside the source** was therefore reading
  outside the buffer — and the first of them was not a renderer but the diagnostic channel's own span
  encode, `s * 4`, which overflowed on the checked multiply and executed `ud2`. The result for a user
  was the worst possible shape a compiler can take: `defer g(u)` where `u` is not yet assigned, a
  program the compiler had correctly decided to refuse, killed `alatyr` with **SIGILL, exit 132 and
  not one byte on stderr**, on `check`, on `-o`, and on all three emit surfaces. The refusal itself
  was right; the compiler simply could not say it. All three producers behaved identically, so the
  same silence covered a `defer`, an `@alloc` and a closure capture through `map`. Locations are now
  classified against the published source-buffer extent before they are encoded or rendered, and a
  synthesized one is re-attributed to the **surface construct** that produced the desugar: the
  arguments of a desugared call are the user's own expressions, so the line named is the line of the
  `defer`, of the `@alloc`, or of the call that captured — the same line the identical refusal already
  named when no desugar was involved. Nothing about an ordinary diagnostic changes: of the 7 816
  per-backend corpus rows, **not one** moves. Two markers have no argument to borrow (the
  `defer { … }` chain's `__deferblk`/`__deferblkend`) and decline to claim a line instead; no
  diagnostic reaches either today.

- **On the wasm backend, a discarded expression statement's value no longer becomes the enclosing
  function's result.** Declarations §5 makes a statement's value discarded — that is what
  distinguishes it from the function's trailing expression — and the parser already models the
  distinction: a fn body is a statement list plus an OPTIONAL trailing expression, so
  `{ q : u64 = 7  q + 1  42 }` is the list `[q := 7, ExprStmt(q + 1)]` plus the tail `42`. The WAT
  emitter asked a weaker question. It marked the body's statement list "tail-valued" whenever the
  function was non-void with no top-level `return`, and on that flag it turns a **trailing**
  expression statement into `(return …)`; since the trailing statement is the last one in the list
  whether or not a tail expression follows it, the module read
  `(return (i64.add (local.get 0) (i64.const 1))) (i64.const 42)` and the declared result was dead
  code. A clean compile, a clean `wat2wasm`, a clean run, and the wrong answer: the reproducer
  exited **8** under `wasmtime` where x86_64, aarch64 and riscv64 all exited **42**. The same flag
  reached a trailing statement `match` as well, so `match p { A => { 5 } B => { 6 } }` followed by
  `43` answered 5 or 6, and a `return` nested inside an `if` did not clear the flag either (wasm 8
  against the other three backends' 40). The explicit-`return` spelling was already right, because a
  top-level `return` cleared the flag by another route. The three native backends never needed a
  flag: they emit the statements — letting a statement's value land in the result register — and then
  emit the trailing expression over it, reading `ex_is_no_tail(Decl.value)` to know whether there is
  one. WASM has to say `drop` instead, and it already knew how; `exprstmt_needs_drop` and the
  `(drop)` arm were present and simply lost to the tail-value arm. The flag now carries the same
  fact the other three read. The value is dropped, not skipped: an expression statement with a side
  effect still executes, which a fixture proves by reading the module global two discarded calls
  mutate. x86_64, aarch64 and riscv64 emission is byte-identical — all 1 954 tracked `test/*.al`
  sources emitted with both compilers, input tree held fixed, gave 1 954 identical digests per
  backend and no diffs. Twenty-one existing corpus sources change their WAT, all of them the same
  shape (a trailing statement before a tail, such as `naked_add`'s `movq  addq  ret()`), and all
  twenty-one still record the same wasm verdict, since they trap on wasm for unrelated reasons and
  the manifest normalizes the backtrace offsets the emission shift moves.

- **`.len` and `.ptr` read through a `ptr([T])` answer the slice's length and pointer, not the run's
  second element.** Types §7 makes a `[T]` binding the two-word `{ptr, len}` view itself — "the view
  *is* the value", the same pair a `str` is — and Memory §4.3 makes `ptr(x)` the address of that
  place, so `deref(ptr(v))` is `v`. Instead every read through the pointer answered **element 1 of the
  underlying run**: with `xs := [7, 3, 9, 11, 13]` and `v := xs[0..4]`, `deref(ptr(v)).len` gave **3**
  where **4** was due, on a program that compiled cleanly and exited normally. All five spellings the
  language offers were affected — a `ptr([T])` parameter, a pointer local spelled inferred
  (`q := ptr(v)`), annotated (`q : ptr([u64]) = ptr(v)`) or bitcast, and the bound form
  (`ss := deref(q)` then `ss.len`) — and one of them had been answering **0** until the previous
  release aligned it with the others, so the wrong answer went from obvious garbage to a
  plausible-looking number. The cause: a slice view local's frame words hold its own pair (pointer at
  the slot, length at the next higher address, exactly as a `str` local's do), but the slot is flagged
  by-reference to mean "index *through* word 0", and the address-of path read that flag as "this slot
  holds a pointer to the whole value" — so `ptr(v)` handed back the **array base** and the read's
  `+8` landed on element 1. The `str` dual of the same shape was already correct, which is why this
  one went unnoticed. Both the address-of path and the inferred-pointer-local recognizer now ask the
  one predicate that already knows which locals carry their own pair, so a by-reference aggregate
  parameter — whose slot really does hold a pointer to the caller's value — keeps the load it had.
  The **bound** spelling needed a second answer: reserving two words is not the same as reserving the
  right two words. `ss := deref(q)` reserved every view pointee as a `str` — two words that are
  indexed by BYTE — because the binder was asked only "is the pointee the two-word pair", which is
  true of `str` and `[T]` alike. A `[T]` bound that way had a correct `.len` and answered byte 1 of
  element 0 for `ss[1]`, so `ss[1]` gave **0** where **20** was due; the same read was refused at
  compile time on one spelling and segfaulted on the other two only because the address was also
  wrong, which means fixing the address alone would have converted a refusal and a crash into a
  silent zero. The binding now reserves an element-indexed slice view carrying the source view's own
  stride, so `ss[i]`, `ss.len` and `for x in ss` all read the pointee, and a `str` pointee keeps its
  byte-indexed binding untouched. x86_64 only: aarch64, riscv64 and wasm fail loud on a view read
  through a pointer, before and after, rather than returning a wrong value. No emitted byte of the
  compiler's own build moves — the new paths are reached by zero expressions in `src/` and `lib/`,
  and by zero of the existing test programs.

- **The `checked_*` overflow-policy operations are reachable at all, and the whole family is
  reachable from a package build.** Concurrency §6.3 gives four explicit overflow-policy families —
  `wrapping_*`, `saturating_*`, `checked_*` (→ `Option(T)`) and `overflowing_*` (→ `(T, bool)`) — and
  says they are "available **everywhere** (no grant)", which §8.5 repeats and the stdlib appendix
  §4.3 makes required v1 content. `lib/base/num.al` has defined all 24 `checked_*` functions since
  the import; nothing could name them. The prelude that carries `num.al` is pulled by a literal
  textual scan of the source bytes, and the trigger listed `wrapping_`, `saturating_` and
  `overflowing_` while the comment printed directly beside it named `checked_` as the fourth. A
  program whose only prelude need was `checked_*` therefore got no base prelude at all and was
  refused with `check: unbound name` — a program the specification calls valid. It looked healthy
  only because `checked_*` returns `Option(T)`: a source that also wrote that type out satisfied the
  **neighbouring** trigger, so `o : Option(u64) = checked_add(a, 1)` answered 42 while the
  byte-identical program with `b := checked_add(a, 1)` was rejected. One word of unrelated source
  text decided whether the program compiled, which is the same property issue #393 evidences from
  the other end — a formatter or an unrelated edit that removed that word could silently flip a
  working program into a rejection. Separately, the entire trigger was gated to single-file
  compilation, so in a **package** build none of the four prefixes resolved: bare `wrapping_add` in
  `src/main.al` answered `check: unbound name` too, and so did the spelling with the result type
  written out. Both are fixed: the fourth prefix joins the list, and the overflow trigger no longer
  asks whether the build is a package, because §6.3's "everywhere" includes a package module. The
  narrower single-file gate stays on the triggers next to it, which are about declarations
  (`Option`, `Slice :=`, `uint :=`, `struct`/`enum`) that a manifest build already owns. The change
  is confined to that one trigger and costs nothing measurable: no source in `src/` carries any of
  the four prefixes at a token boundary — every occurrence is inside a comment, inside a string
  literal, or in the interior of a longer identifier such as `unchecked_mode` — so the compiler's own
  build emits byte-identical assembly, and re-deriving all 7 816 existing corpus rows across all four
  backends with the fix in place reproduced the oracle byte-for-byte, with zero rows changed. The
  prefix match stays open-ended, so an identifier that merely *starts* with one of the four names
  (`checked_total`) still over-triggers and injects a prelude it never calls, which dead-code
  elimination drops; that was already true of the three prefixes it joins, and an over-trigger costs
  a prelude while an under-trigger refuses a valid program. x86_64 answers 42 for every shape; the
  non-x86 surfaces trap loudly (aarch64/riscv64 133, wasm 134) on this library exactly as they
  already did for `test/overflow_policy.al`, and the qualified `base::num::wrapping_add` spelling is
  still refused for a different reason — the missing `pub` markers on the base tier, which is its own
  unit.

- **A comparison whose operand is a struct literal or a payload-carrying variant construction now
  compares componentwise, instead of comparing both operands as the constant zero.** Stdlib §2.6
  defines `eq(in a : T, in b : T) -> bool` with "default = componentwise field equality" derived
  structurally over `typeinfo(T)`, and Comptime §5.5 gives the enum body normatively: the same
  variant compares the whole payload by recursing with the operator, a different variant is not
  equal. The prelude's derive was already a faithful transcription of that; what declined was the one
  gate that decides whether a bare `==` reaches it. That gate classified an operand by reading its
  **frame slot**, so it answered only for a plain variable — and a constructor expression has no
  slot. The operand then fell through to the scalar comparison, where a multi-word aggregate in a
  scalar value position materializes as the **constant zero**, and the emitted code for
  `P(x = 5, y = 7) == P(x = 5, y = 9)` was literally `pushq $0` / `movq $0, %rbx` / `cmpq` / `sete`.
  Both directions were wrong, on structs, `Option` and payload enums alike, on programs that compiled
  cleanly and exited normally: `Option.Some(1) == Option.Some(2)` answered **true**,
  `Option.None == Option.Some(5)` answered **true**, `P(5,7) == P(5,9)` answered **true**, while
  `o == Option.Some(1)` and `p == P(x = 5, y = 7)` answered **false** for an `o` and a `p` bound to
  exactly those values. Two shapes were right only by coincidence — two equal literals compared their
  two zeros — and they now answer through the derive rather than by accident. Ordering was affected
  identically and did not even reach its own refusal: `p < P(x = 5, y = 9)` answered "not less".
  `Option` is the most-used enum in the language, which is what makes this the worst member of the
  class; a discriminant-only enum was never affected, because a payload-free variant materializes its
  discriminant correctly, and that is why the common case looked healthy. Two shapes that cannot be
  answered correctly yet become **located rejects** rather than answers: ordering over a
  payload-carrying enum (the derive's `lt` enum arm has no emit, the same refusal two enum locals
  already got) and a comparison between two **different** aggregate types (the derive is
  monomorphized on one type). x86_64 only: aarch64 and riscv64 fail loud on every shape here before
  and after, and wasm still answers two of them wrongly by comparing two freshly allocated scratch
  blocks' addresses — a separate defect, tracked on its own, and deliberately not recorded as
  expected by any gate row. No emitted byte of the compiler's own build moves: the routing is reached
  by **zero** expressions in `src/` and `lib/`, and of the 1 589 existing test programs exactly one
  changes emission (a struct's enum field bound to a local, compared against a nullary variant, which
  keeps its answer and now gets it through the derive).
- **`str_at` is published, and its first parameter is the address as a `usize` the specification
  writes.** Stdlib appendix §3.6 enumerates five `str` operations, and §8.2 items 2 and 6 make the
  enumerated set required v1 content; Modules §3 fixes a library's public API as exactly the
  `pub`-chain-to-root-reachable surface. Four of the five carried the marker. `str_at` did not, so
  `base::str::str_at(p, n)` — the raw inverse of `bytes`, a `str` view over `n` bytes at an address —
  was refused from any module that is not a descendant of `base::str` (`check: invalid`, exit 1),
  even though the bare and UFCS spellings resolved: the unqualified arm applies no visibility test
  (#403), which is a separate defect and not the surface being published. The declaration also read
  `fn(p : ptr(u8), n : usize)` while §3.6 writes `str_at(in p : usize, in n : usize) -> str` and its
  prose fixes the one-step `usize → ptr(u8) → [u8] → str` chain; the `usize` is the point of the
  design, because fabricating a pointer from an integer needs an `unchecked` grant (Memory §4.5) and
  §3.6 puts that grant inside this one function instead of at every call site — the module's own doc
  comment already described it that way. Both are corrected together, since publishing the old
  signature would have published the divergence. `in` is the default direction, so it adds nothing.
  Semantics, representation and every other `str` operation are untouched, and nothing is emitted
  differently — the seed's own 1 205 559-line GAS output is byte-identical across the change, and so
  are the two seed-built compilers.
- Not one of the tree's `str_at` callers needed editing, and the reason is a **documented
  compatibility rule**, not a missing check. `src/sema.al` does compare a call argument against the
  declared parameter type — the CALL-ARG conformance block at `:5781`–`:5800` (`agg_scalar_bad`,
  `call_arg_lit_incompatible`, and `expr_call_result_ty` against `callee_param_ty`) — and it does
  reject: a struct passed to a same-file `fn(p : usize)` is `check: type mismatch`, measured. What
  licenses an address in either spelling is `tag_compat` (`src/sema.al:224`–`:231`), which makes
  int(1) and pointer(5) compatible in **both** directions, with the rationale spelled out at
  `:216`–`:223`: the self-host models an AST or allocator handle as a bare `usize` in some signatures
  and a typed `ptr(T)` in others and flows one into the other freely, and the lower already lowers
  that seam identically (MEM-7/8, I11, D-usize→ptr). Measured in the position where the check does
  fire: `ptr(u8)` into a `usize` parameter is accepted, `usize` into a `ptr(u8)` parameter is
  accepted, and a struct in the same position is rejected. So both signatures accept both spellings
  of the address, and the nine `str_at(x.ptr, …)` callers keep working by rule rather than by
  accident — there is no migration owed in either direction, and this change is not a compatibility
  gamble. For scale: of the 2 897 `str_at(` call sites in `src/` and `lib/`, 2 255 spell the first
  argument `str_at((src + <off>), n)`, and `src : ptr(u8)` is declared 1 821 times in `src/` against
  `src : usize` exactly once (`src/parser.al:580`) — the tree writes that address both ways, which is
  precisely the seam `tag_compat` exists to model.

- **An undeclared name used as an operand inside an `if` or `while` condition is refused, instead of
  choosing a branch by a garbage read.** Declarations §5 makes scope lexical and block-structured — a
  name is visible in the scope where it is declared and in all nested scopes — and §7.2 makes a local
  visible only from its point of declaration onward, so a name declared in a sibling function, or
  nowhere at all, is visible in neither. The compiler already said exactly that (`check: unbound
  name`) in binding position, in `return` position, in tail position, and for a bare name that is the
  *whole* condition. Only the **operands inside a condition** slipped through, and the consequence was
  not a stable `false`: `if vv.ek == 4 { … }` took the `return` branch when a same-named local existed
  in a sibling function (exit 62) and fell through when no `vv` existed anywhere (exit 73) — two
  spellings of one ill-formed program choosing *opposite* branches off whatever frame word the
  position resolved to. `while vv < 3 { … }` entered the loop. The statement-position name walk
  answered "clean" for every binary node, and the `while` condition ran no name walk at all, which is
  why even a bare undeclared name as a whole `while` condition was accepted; a discarded `vv + 1`
  expression statement was accepted for the same reason. All of those are now the located refusal the
  neighbouring positions already produced, identically on x86_64, aarch64, riscv64 and wasm, because
  `check` is one frontend. This can only *reject*: an operand is walked for name existence only, so
  the struct field-name fence — which is not reliable when a user type's name collides with a
  library generic — is not carried into a new position, and no valid program in the 1 925-program
  corpus, or in the compiler's own 15 628 compound-condition lines, changes verdict or diagnostic.
  Worth more than its size for one reason beyond the defect: it silently **corrupts measurements**.
  An instrumented build whose predicate references a name it should not have reports confidently and
  wrongly while the build stays green — that is how a route census produced false markers that a
  byte comparison of the emitted GAS later contradicted. Until this landed, a census claim needed
  that companion measurement to be evidence at all.

- **An enum-variant constructor whose payload count differs from the count its variant declares is
  refused.** Types §9.4's first bullet is that the language "never zeroes an uninitialized binding on
  the programmer's behalf" — there is no implicit zero-initialization — so for `Pay := enum { A(u64),
  B(u64, u64) }` the expression `Pay.B(7)` leaves the second payload word with no value at all. It
  used to compile clean on all four backends and answer 7, which is to say it read that word as an
  implicit zero the specification does not provide. The reverse spelling was just as quiet: three
  values into a two-payload variant compiled and answered 15, silently dropping the argument the
  author wrote. So were both directions on a one-payload variant, a zero-payload variant handed a
  value, and the prelude's generic `Result`/`Option` instances. All of them are now one located
  `check` refusal that names the offending **variant** and the count its declaration asks for, so the
  message tells the author which variant of the enum is wrong and what it wanted; being `check`'s, it
  is byte-identical on x86_64, aarch64, riscv64 and wasm. This can only reject, and it rejects only a
  program the specification calls ill-formed: the expected count is read from each variant's own
  declaration rather than compared against a fixed number or against the enum's widest variant, and
  neither of the two nullary spellings (`E.N`, `E.N()`) nor any of the 1 937 corpus programs changes
  verdict or diagnostic. Raw-union members are deliberately untouched — §6.3 makes their
  constructor's byte-clear part of that operation's canonical representation, a different argument
  from §9.4's, and their arity rule is its own unit.

- **Indexing a module-level `[str; N]` global now reads the element it names.** `G[k][j]` — the byte
  at index `j` of the `str` element `k` — answered **5** where **90** was due, and the element used as
  a whole `str` value was worse: `str_eq(G[k], "…")` was unconditionally **false** and
  `bytes(G[k])[j]` trapped on a zero length. The same spellings over a `[str; N]` **local** have been
  correct since 0.1.x, so two spellings of one read disagreed on a clean compile, and the wrong answer
  was a real string byte rather than obvious garbage. Two defects stacked. Types §7 makes each element
  a two-word `{ptr, len}` view, but a `str` literal has no scalar initializer value, so the global's
  storage imaged as **one `.quad 0` per element** — a null pointer, no length word, and a one-word
  stride — meaning no addressing could have answered correctly. On top of that every str-element
  recognizer resolves its root through the frame-slot map, which a global has none of, so the element
  fell to the empty-pair default and the nested byte read fell to the untyped element-address tail
  (frame slot 0 before 0.1.x's refusal, a located refusal after it). Both `mut` and non-`mut` roots
  are covered, the element index is bounds-checked against the array's static `N` and the byte index
  against that element's runtime length, and a frame local that shadows the global name keeps its own
  local path. Two shapes stay **loud** rather than becoming plausible wrong values: a whole-element
  write `G[i] = <str>` (the only available store arm would put one word mid-element, corrupting a
  neighbour) and an array global that mixes `str` elements with non-str ones (element 0 fixes the
  stride). `G.len` on any array global, and `for s in G` over a `[str; N]`, are separate reads and are
  unchanged. aarch64, riscv64 and wasm still trap on every `str` index rather than answering a wrong
  value, exactly as they do for the local spelling. No emitted byte of the compiler's own build moves:
  `src/` and `lib/` declare no module-level array global at all.
- **A dead binding whose name merely begins with a prelude trigger word no longer decides whether a
  program compiles.** The ambient prelude a single file receives is chosen by scanning its source
  text, and every bare-name trigger checked the leading word boundary. The result- and option-type
  triggers had no trailing one, so `Result_marker_unused := 0` — declared, never read, of no
  interest to any line below it — matched and pulled in the whole base closure. A file using only
  `assert` and `min`, two prelude names reachable by no trigger of their own, therefore compiled and
  ran with that binding present and was refused without it. Both triggers are now matched on both
  sides. Every spelling a real use writes (`Result(T, E)`, `Result::Ok`, `Result.Err`, `Option(T)`,
  `Option.Some`, and the `Result :=` / `Option :=` declaration vetoes) ends at a non-identifier byte
  and keeps firing, so no file in the tree changes the prelude it receives: measured over
  `package.al` plus every tracked `src/`, `lib/` and `test/` source, 885 result-type and 757
  option-type trigger hits already carried a trailing boundary and zero fired by prefix match alone.
  A program that was relying on the accidental match is now refused exactly as the same program
  without the binding already was — the text-scan limit itself is unchanged and still tracked.

- **A `Slice(T)` element store through a nested field path is now typed.** `outer.leaf.values[i] =
  <wrong-typed value>` was accepted with `check` and `build` both returning 0: the element-type
  resolver walked its owner with an already recursive resolver, but a guard in front of that call
  demanded a bare local root, so a two- or three-owner path left the element type UNKNOWN and any
  value passed. Reading the slot back then answered the string's address — 6 in one measured run.
  A wrong `str`, a `bool` into `Slice(u64)`, and a struct value into a scalar element are now all
  refused with the same located `type mismatch` diagnostic the single-owner spelling already
  produced, on all four backends, because the check is in `sema`. Valid nested and deep stores of
  the declared element type keep working, and the single-owner and fixed-array-field spellings are
  untouched. Element stores through a nested owner whose field is a fixed array, and through one
  type alias of `Slice(T)` under a nested owner, remain unchecked: the x86_64 lowering declines
  both places at build time before an element type would be consulted.

## 0.2.0 — 2026-09-07

- An out-of-range `bytes(s)[i]` now **traps** instead of answering with the byte that happened to
  follow the string. `str` is `[u8]`, and every other spelling of a view byte read — `s[i]` on a
  `str` local, `"abc"[i]` on a literal, `arr[k][j]` on a `[str; N]` element — already compared the
  index against the view's runtime length and stopped there. `bytes(s)[i]`, the spec-canonical
  spelling, was the one that did not: the read completed, the program exited normally, and the value
  was whatever byte sat past the run. Inside an `unchecked` scope the check is dropped exactly as it
  is for every other index, so code that deliberately opts out is unaffected. This is x86_64; the
  other three backends already stop loudly on every `str` index.
- **Binding the pointee of an inferred `ptr(str)` local reads the pair, not one word.** Stdlib
  appendix §3.5/§3.6 fix `str` as the two-word `{ptr, len}` pair and Memory §4.1 makes `deref(q)` an
  ordinary read through the pointer, so `q := ptr(s); ss := deref(q); ss.len` must answer `s.len`. It
  answered **0**, while the same binding on an annotated (`q : ptr(str) = ptr(s)`) or bitcast local
  answered the pointee, and so did the *inline* `deref(q).len` on the very same inferred local — two
  spellings of one read disagreeing on a clean compile. A binding is decided twice: the frame-slot
  collector has to reserve two words for `ss` and the assign emit has to write both. Both gates asked
  for the pointee's *type span*, which the annotated and bitcast spellings carry in their own source
  text and the inferred one cannot — `str` is structural, so no `str` span exists anywhere in the
  source to hand back. The reservation fell to one scalar word and the store wrote only the pointer
  word, so `ss.len` read a never-written neighbouring slot (`ss.ptr` was accidentally right, because
  word 0 of the pair *is* the pointer). Both gates now also accept the boolean source scan the inline
  read already uses, so the two spellings answer from one shared fact and cannot drift apart again.
  The span-valued resolver is deliberately left alone: it is shared with the `deref` load/store width
  queries and cannot answer this shape anyway. Purely additive — every pointer whose pointee type was
  already recoverable keeps its exact previous lowering, `ptr(<struct>)` and `ptr(<scalar>)` locals
  are untouched, and no emitted byte of the compiler's own build moves, because `src/` and `lib/` bind
  no `deref` of an inferred pointer-to-view local. aarch64, riscv64 and wasm still trap on `str`
  behind a pointer rather than answering a wrong value, exactly as they did before.
- **A struct field whose type is a raw `union` is stored at its own width on wasm, aarch64 and
  riscv64, so the field after it no longer reads a wrong number.** Types §6.3 sizes a union as the
  widest member with the members overlapping at offset 0 and **no** discriminant word, which is a
  different layout from an `enum`'s `{disc, payload…}` — but a `union { m(T), … }` parses into the
  same declaration and the same `U.m(v)` construction an enum does, so every enum-shaped store on
  those three backends claimed it: each one wrote `1 + max-arity` words with a tag at word 0 (one
  word too wide *and* one word out of place) or fell back to storing a single pointer/discriminant
  word where the field reserved more. The field itself was never where the wrong value showed up:
  every reader still resolved the field's real offset, so the corruption landed in the **neighbour**.
  `Lead(lead = 4, p = u, n = 9, big = …)` over `union { a(u64), b(u64) }` read `l.n` as the union's
  payload instead of 9 — a clean compile, exit 0, no trap. All five ways a union value can feed such
  a field are fixed: the constructor literal, a union-returning call, a local bound to either of
  those, and a union parameter. Three of them *appeared* correct on wasm before, and that was a
  coincidence worth naming: a one-word union field and a one-word pointer store agree by
  construction, and the same programs over a union with a two-word member answered wrongly on all
  three backends. A member that is not single-payload (multi-payload, which §6.3 leaves undefined,
  or a payload-free member) now **traps** at that store instead of writing a short one. x86_64 was
  already correct on every one of these shapes and is untouched, as is every `enum` field — the
  union arms are gated on the declaration actually being a union, so no emitted byte of the
  compiler's own build moves. Reading a union *member* back (`u.m`, `s.p.m`) remains a loud refusal
  on the three non-x86 backends and is a separate gap.

- **A generic call with more than three comptime type parameters is refused instead of answering the
  wrong value.** On x86_64 a call to a generic fn with **four** type parameters compiled cleanly,
  linked, exited normally and returned `0` where 42 was due — the silent class. The arity is measured,
  not assumed: 1, 2 and 3 type parameters answer correctly and **4 is the first bad one** (5 and 6 fail
  the same way). The monomorphization machinery carries three type arguments in every column it has
  (`LCtx`'s parameter bindings, the instance record's type-arg slots, the three type-tags of an
  instance label, the three erase positions of the call-argument emitter), so with four type
  parameters only three leading type arguments were erased: the fourth type *name* stayed in the
  runtime argument list, was evaluated as if it were a variable, and its unwritten frame slot was
  passed as value argument 0 while every real value argument shifted one place down. The instance
  label kept three tags for four type arguments. aarch64, riscv64 and wasm already refused the
  identical shape loudly — an `ld` undefined reference, a SIGTRAP, and a module `wat2wasm` rejects —
  so x86_64 was the only wrong backend of the four, and the refusal makes them agree. Lowering four
  type arguments correctly is a capability increment tracked on issue #476, which stays open for it;
  the working spelling today is to carry the extra types as ordinary value parameters or to split the
  call. A four-type-parameter generic that is *declared but never called* still builds — the fence is
  on the call, as it already was on the three cross backends. Nothing in `src/`, `lib/` or the test
  corpus declares such a generic, so no working program changes and no emitted byte moves.
- **A range slice indexed directly, `xs[lo..hi][i]`, reads the view's element on x86_64.** Grammar
  §3.4 spells a postfix chain as `primary { postfix }` with both `"[" expr "]"` and the range form
  among the postfix operators, so this is one primary followed by two postfix steps and needs no
  intermediate binding — yet the two spellings of the same access disagreed. `v := xs[1..3]; v[0]`
  answered 42 while `xs[1..3][0]` answered **0**, a word read out of the caller's own frame, because
  the view the range produces has no frame slot for the element-address path to resolve; the previous
  entry turned that silent read into a located refusal, so the same program then failed to compile at
  all. The offset is now honoured (`lo` is added to element 0's address with the element's own stride,
  the same two words the bound spelling stores into a slice local), and the view's runtime length
  becomes the bounds check, so an index past the view's end **traps** instead of reading the base
  array beyond `hi`: `xs[1..3][2]` raises SIGILL rather than returning `xs[3]`. Scalar word elements
  only — a byte, float, struct, enum or `str` element array, and a `str` range slice (`s[lo..hi][i]`),
  keep the located refusal, because the element *width* on those paths is chosen by queries that only
  recognise a named base and would pair a correct address with a word-wide load. aarch64, riscv64 and
  wasm have their own element-address paths, are untouched, and still trap at runtime on this spelling
  rather than returning a wrong value; the bound spelling remains correct on all four. No emitted byte
  of the compiler's own build moves: the recognizer fires only on a range-slice base, and the
  compiler's `src/` and `lib/` contain none.

- **An index whose base is not a named place is refused instead of reading the caller's frame.** The
  generic element-address tail of the x86_64 lowering composed `base + i * stride` out of the base's
  frame slot, and the slot lookup answered *entry 0* — the first local of the enclosing frame — for
  every base it could not name. Nine spellings therefore compiled with `rc 0` and returned a plausible
  word out of the caller's own frame: `xs[lo..hi][i]` gave 0 where 42 was due, `s[lo..hi][i]` gave 6
  where 98 was due, a store through `xs[lo..hi][i] = v` vanished, and `[a, b, c][i]`, `deref(p)[i]`,
  `(if c { xs } else { ys })[i]`, `ptr(xs)[i]`, `Slice(T)(ptr = …, len = …)[i]` and a module-global
  `[str; N]`'s `G[i][j]` all read the frame instead of the value. Each of the four defects fixed before
  this one — a `str` literal base, a `[str; N]` element base, `unchecked a[i]`, and the range slice —
  was fixed by adding one more recognizer *in front of* that tail while the tail's own default kept
  answering wrongly, so the next unrecognized shape was another silent wrong value. The tail now names
  the offending source line and refuses. Every base shape that legitimately reaches it was enumerated
  by measurement, not assumed: 1161 arrivals over the 1564-program test corpus and the compiler's own
  `src/` + `lib/`, every one a named local or parameter, so no working program changes and no emitted
  byte moves. Grammar §3.4 makes each refused spelling well-formed, so each one's correct lowering is a
  future recognizer above the tail rather than a wider default inside it; the range-slice base is
  tracked as issue #422. The working spelling in every case is to bind the base to a local first
  (`v := <base>; v[i]`), which all four backends already lower. aarch64, riscv64 and wasm have their
  own element-address paths, are untouched, and already trap at runtime on these shapes rather than
  returning a wrong value.

- A **`{}` hole filled by a bare unary-minus expression** now prints its value on **x86_64**, instead
  of printing **nothing at all**. `print("a=[{}]\n", -4)` printed `a=[]` and
  `print("c=[{}]\n", -9223372036854775808)` printed `c=[]`, on a program that compiled cleanly and
  exited with the right code — so no gate stage that reads an exit status could see it. The same value
  written `0 - 4` printed `-4` correctly, and after the previous entry's fix the aarch64, riscv64 and
  wasm backends printed **both** spellings correctly, which left x86_64 as the one divergent surface
  for this one spelling. The cause is that the parser desugars unary minus to
  `Unchecked(Bin(17, Num(0), x))` so the negation lowers as guard-free two's-complement, and every
  shape test in the x86_64 hole expansion reads the node's outer kind — `Expr::Unchecked`, not
  `Expr::Bin` — so no renderer arm matched and the hole contributed zero bytes. `unchecked` is a
  verification mode and never a type, so the hole now routes on the same `lit_arith_i64` predicate the
  other three backends already use, and all four surfaces read one decision. The `0 - 4` spelling still
  matches the arithmetic arm first and its emitted bytes do not move; measured with the input tree held
  fixed over all of `test/*.al`, x86_64 emits one differing artifact (the new fixture) and aarch64,
  riscv64 and wasm emit zero.
- **A `{}` hole the expansion cannot type is now refused with its source line, where it used to print
  the empty string.** This is the same silent class as above and the reason it went unnoticed: the hole
  emitted nothing while the statement, the enclosing call and the process exit code all reported
  success. Four spellings reached that sink and are now a located refusal on x86_64: a negated name
  (`-x`), a negated call (`-f(3)`), a negated float literal (`-1.5`) and a negated float local. Each
  was already printing the wrong thing — the empty string on x86_64, the unsigned 64-bit magnitude or
  a float's bit pattern read as an integer on the other three backends — so no program that printed a
  correct value stops compiling. Rendering them needs the type layer rather than a shape-local peel and
  is tracked separately; measured over the compiler's own `src/` and `lib/`, all 1559 tracked
  `test/*.al` and the 421 remaining tracked `.al` files, nothing else reaches the refusal.
- **A struct field fed by an enum *place* keeps the enum on wasm too** — and the field *after* it stops
  reading a wrong number. `e := mkb()` and then `Lead(lead = 4, p = e, n = 9)` answered `l.n == 0`
  where 9 was due, on a program that compiled cleanly, exited zero and trapped nowhere; x86_64,
  aarch64 and riscv64 all answered correctly. This is the **third** distinct defect at that one wasm
  aggregate writer, and the entry below is the second: that one fixed the shape whose feed is an
  enum-returning **call**, written inline in the constructor, and its new arm matched a call and
  nothing else — deliberately, because a **place** has no call to make and needed its own
  materialisation. So a local or a parameter whose slot already holds the `{disc, payload…}` block was
  still none of the writer's known shapes and fell through to the scalar fallback: one store of the
  place's **block address**, reported as **one** word, while every reader still resolved the field's
  real offset. All three place spellings were affected — a local initialised from a call, a local
  initialised from an enum **literal**, and an enum **parameter** — because they are named by three
  different halves of the same resolver, and the same feed one level down inside a nested struct
  literal was affected too. The enum **literal** written inline in the constructor answered correctly
  throughout, which is again what separates a store-width defect from the enum-field **read** (issue
  #449, which is loud on wasm and unchanged). The single query that asks whether an expression delivers
  an enum by address now answers for a place as well as for a call, so the two feeds share one width
  decision instead of two that can drift; it reuses the parameter/local resolver that value-position
  `match` and the wasm comparison guard already use. Two shapes are deliberately left alone: an enum
  whose variant carries a **wide** payload, which this backend's enum machinery does not model at all,
  and a raw **union**, whose field overlaps its members at offset 0 with no discriminant word — sizing
  a union like an enum moved its neighbour, measured, so the union place feed keeps the behaviour it
  had. Feeding a struct's enum **field** into another struct's enum field remains a loud refusal on
  every backend.

- **A struct field fed by an enum-returning call keeps the enum on wasm too** — and the field *after*
  it stops reading a wrong number. `Lead(lead = 4, p = mkb(), n = 9)` for `mkb() -> Pay` answered
  `l.n == 0` where 9 was due, with a clean compile, a zero exit and no trap anywhere. The entry below
  fixed this shape on the other three backends and left wasm out on the stated grounds that a struct's
  enum field there "traps per #449". That is only half true, and the silent half is the worse one: #449
  is the enum-field **read**, which is loud, while this is the store's **width**, so a program that
  never reads the enum field back — one that uses only its scalar neighbours — got a wrong answer
  quietly. The same struct built from an enum **literal** answered correctly throughout, which is what
  separates the two mechanisms: a read defect would have taken the literal spelling down as well. On
  wasm an enum-returning call yields the i64 **base address** of a freshly bump-allocated
  `{disc, payload…}` block, and the flattened aggregate writer recognises a struct literal, an enum
  literal and an array literal — a **call** is none of those, so the field got that pointer as its
  single word and the writer reported **one** word. The block reservation was already the flattened
  width, so there was room; only the store was short, and every following field was written
  `max_arity` words too early while its reader still resolved the field's real offset. The call arm now
  parks the returned base in the whole-aggregate word-copy scratch local and copies the full
  `1 + max_arity` words inline at the field's own offset, exactly as the enum-literal arm beside it
  lays a literal out. Sizing is by `max_arity` and not by the called variant's arity, so the
  one-payload-word variant of a two-word enum cannot pass by coincidence. A **payload-free** enum call
  is one word and leaves its struct all-scalar, so it never reaches the new arm and its emitted text is
  byte-identical. Reading a struct's enum field on wasm is still issue #449 and still refuses loudly.

- **A struct field fed by an enum-returning call keeps the enum** on x86_64, aarch64 and riscv64.
  `Boxed(p = mk())` for `mk() -> Pay` answered 0 on x86_64 and 100 on the other two where 105 was due,
  while the same value bound to a local first (`e := mk()`, then `Boxed(p = e)`) answered 105
  everywhere — so this was the last row of a feed matrix whose own reference backend was wrong, which
  is why making the non-x86 backends loud and comparing them against x86_64 could not settle it. The
  bind-to-a-local control does settle it: it is correct on all three, before and after. Two different
  mechanisms produced the two numbers. On x86_64 the struct-literal field loop recognises a struct
  literal, an enum literal, a `str`, an aggregate variable and an array literal; a **call** is none of
  those, so a multi-word enum field fell into the array branch, which matches only an array literal and
  emitted **nothing at all** — the call was never made and the field kept whatever its frame slot held.
  On aarch64 and riscv64 the payload writer's scalar fallback stored **one** return register and
  reported **one** word, so the discriminant landed, every payload word was dropped, and every field
  after the enum field was written one word too early. Types §6 and Control Flow §5.2 make the field
  hold what the call returned, payload included. x86_64 now delegates to the same whole-enum deliverer
  the `h.t = mk()` assignment already used; both other backends copy the call's full `1 + max_arity`
  width out of the return registers and report it, so a following field stays aligned. A
  **payload-free** enum call is one word, was already correct, and is declined by both new writers on
  purpose, which leaves the emitted text byte-identical for every program that has one. The
  pointer-relative twin — the same feed into an array element at a runtime index — is fixed with it.
  wasm is unchanged: a struct's enum field there is issue #449's by-reference block and still refuses.

- A **negative `{}` hole whose operand carries no `iN` annotation** now prints with its sign on
  **aarch64**, **riscv64** and **wasm** too. The previous fix gave those three backends a signed
  renderer and selected it with the same signedness oracle `/`, `%` and `shr` route on, which proves
  an annotated `iN` param or local, an `iN(x)` conversion and a shift over one of those — and nothing
  else. Four ordinary shapes carry no annotation anywhere for that scan to read: an un-annotated local
  initialised from arithmetic (`inferred := 0 - 5`), an element of an `[i64; N]`, a call whose declared
  return type is `i64`, and a bare literal-arithmetic hole (`0 - 4`). All four still printed the
  unsigned 64-bit magnitude — `18446744073709551611` where x86_64 printed `-5` — with a clean compile
  and the correct exit code, which is why the exit-code cross-target sweeps stayed silent. Functions
  §7.1 routes every hole through the scalar rendering layer and gives a hole with no other type the
  default numeric type `i64`; Stdlib appendix §2 then requires "a leading `-` for a negative
  two's-complement value" on every surface. The three backends now recover the same three source facts
  x86_64 already recovers — an array type's declared element type, a callee's declared return type,
  and §7.1's `i64` default for literal arithmetic — in a predicate **layered on top of** the arithmetic
  oracle rather than folded into it: widening that oracle would move division and shift selection on
  three backends, which was measured, not assumed (one extra `Expr::Index` arm turned `arr[0] / 2` from
  `udiv` into `sdiv` and `shr(arr[0], 1)` from `lsr` into `asr`). The unsigned oracle is still asked
  first and still wins, so a `: u64` local, a `[u64; N]` element and a `u64`-returning call keep the
  unsigned renderer and their exact previous bytes — measured with the input tree held fixed over all
  of `test/*.al`: x86_64 1175 emitted artifacts and 0 differing, aarch64 1229 / riscv64 1229 / wasm
  1231 with exactly one differing each, the new fixture. Float, `str` and aggregate holes still reach
  the one integer renderer on those backends and remain a separate defect.
- An **inline field read through a `ptr(str)` local** now reads the pointee, instead of answering
  **0**. Stdlib appendix §3.5/§3.6 make `str` the base tier's two-word `{ptr : ptr(u8), len : usize}`
  pair and Memory §4.1 makes `deref(q).len` an ordinary read through the pointer, but
  `s := "a,bc"  q := ptr(s)  deref(q).len` built cleanly and answered **0** for a four-byte string,
  and `deref(q).ptr` answered a **null** pointer. All three ways of spelling the local were affected
  — inferred (`q := ptr(s)`), annotated (`q : ptr(str) = ptr(s)`) and `q := unchecked
  bitcast(ptr(str), ptr(s))` — while the same read through a `ptr(str)` **parameter**, the same read
  over a **user struct**, and binding the pointee first on an annotated local (`ss := deref(q)` then
  `ss.len`) were all already correct, so two spellings of one read disagreed. The pointee-view read
  keyed only on a slot MARKER that a parameter carries and a local carries in none of the three
  spellings; it now also consults the pointer local's own annotation or `bitcast` target, and
  recognises the address of a `str` local. One shape of this class is **still open** and unchanged:
  the *bound* form on an *inferred* local (`q := ptr(s)` then `ss := deref(q)`) still copies one
  word, because that binding recovers its pointee from a type spelling the inferred local does not
  have. x86_64 only: aarch64, riscv64 and wasm refuse these shapes fail-loud rather than answering
  the wrong value (measured, unchanged). The compiler's own emitted assembly is byte-identical, and
  across all 1551 programs in `test/` no expression changed which lowering arm serves it.
- **A `match` on a nested enum place (`o.inner.t`) now takes the right arm** on x86_64, in every
  `match` form. Control Flow §5.3 makes `match` one expression with one meaning — the arms are tested
  top to bottom and the first matching arm wins, whatever the scrutinee expression is — but a
  scrutinee whose base was ITSELF a field was never recognised as an enum at all. It fell into the
  integer-scrutinee path, where an enum pattern arm carries no scalar literal, so every arm compared
  the value against 0 and **no arm matched**: the wildcard won, or the no-arm fallback answered 0.
  The program built cleanly and returned that number. Unlike the one-level case fixed earlier, this
  hit all four spellings — tail expression, value expression, braced statement, and the usual
  workaround of binding the field to a local first. That last one failed for a second reason: the
  binding `x := o.inner.t` reserved a plain scalar slot, so only word 0 — the discriminant — was
  copied. Its being the *right* discriminant is exactly why `x == Tag.Green` kept answering correctly
  and made the defect look like a `match` bug alone; a payload-carrying enum bound that way lost its
  payload words outright. Both halves now resolve the whole chain through one walk that accumulates
  the word offset, so a field at any depth reaches the same materialisation a one-level field does.
  A struct **parameter** arrives by reference, and reading a multi-word leaf through that pointer
  stays the located reject it already was. x86_64 only: aarch64, riscv64 and wasm have no enum-match
  lowering and trap fail-loud on this shape, before and after. The compiler's own emitted assembly is
  byte-identical in both directions with the input tree held fixed.
- Three more **right-hand sides of an assignment to a struct's enum field** (`h.t = <rhs>`) are no
  longer **dropped** on x86_64: an enum field of another struct (`h.t = s.t`), an enum array element
  (`h.t = xs[0]`) and a branch value (`h.t = if c { … } else { … }`, and its `match` spelling). Types §6
  makes the assignment observable at the next read of that place, but each of these built cleanly, ran
  normally and read back the variant the struct **literal** had written. The previous fix taught the
  whole-enum writer an enum place and an enum-returning call; every other value kind still fell into a
  wildcard that emitted **no instruction at all** while the caller reported the store as done. A
  payload-carrying enum lost its payload words the same way, and an enum tuple component was dropped
  too. All of these now store the complete `{disc, payload…}` block, reusing the deliverers the
  corresponding `x := <rhs>` local binding already used, so a shape that binds correctly assigns
  correctly.
- **A right-hand side the writer cannot address is now refused, not silently ignored.** That wildcard
  is the reason this class kept recurring: emitting nothing looks like success to every caller, so the
  program answers stale with exit status 0. It now reports whether it wrote anything, and a shape it
  cannot deliver — a mutable-global enum source, a `deref` of an enum pointer — is a located
  diagnostic naming the right-hand sides that do work. Those two programs previously compiled and
  answered a stale field. No program in this repository, its standard library or the compiler's own
  source reaches that refusal, and the compiler's emitted assembly is byte-identical. x86_64 only:
  aarch64 and riscv64 refuse this shape fail-loud, and the wasm field read is a separate defect.
- **`unwrap` / `expect` over an `Option` whose payload is a generic struct** now deliver the whole
  value instead of its first word. Stdlib appendix §2.3 fixes the optional shape and §4.2 makes
  `unwrap` the present-arm extraction; Types §4 gives the binding the initializer's type, so
  `unwrap(Pair(u64, u64), Option(Pair(u64, u64)).Some(v))` is `v`. Three source scans classified the
  substituted type-argument by its FULL text — `Pair(u64, u64)` matches no declaration name, only
  `Pair` does — so the generic enum-value parameter kept the un-substituted one-payload-word layout,
  the effective `-> T` return was classified as a scalar, and the tail-`match` payload was bound as a
  bare scalar. The program compiled cleanly and answered a wrong value: the second field read back as
  `0` in the minimal case, and driving `alloc::hashmap::next` — whose `Entry(K, V)` is exactly such a
  struct — through `unwrap` answered the **key** in place of the value. A `match` over the same
  `Option` was correct throughout, which is what made the defect invisible. Nothing changes about
  `Option`'s representation, about `match` lowering, or about `alloc::hashmap`; the non-generic
  payload was already correct and stays byte-identical, and the compiler's own emitted assembly is
  byte-identical, so the frozen seed still reproduces the tree.

- Two **overloads of one generic function** in one module no longer share a linker symbol. A generic
  instance is labelled `<module>__<fn>__<typetag>`, built from the **type arguments alone** — the value
  parameters took no part in it — so at one instantiation two declarations that overload resolution
  keeps apart collapsed onto one symbol, which Modules §6.7 forbids. **Arity** decided which face that
  wore, and both are now closed. Where the overloads shared an arity the resolver answered *both* call
  sites with the last-declared one, a single body was emitted, and the other call read it: a clean
  compile, exit 0, and a **wrong value** — a `pick(u64, A(…))` over a one-word `A` returned the second
  word of the `B` overload's argument. Where the arities differed each call site selected its own
  declaration, both bodies were emitted under one `.globl`, and the build died in `as` with
  ``symbol `…' is already defined`` — a raw assembler error with no source location. The generic path
  now joins the per-signature overload machinery the non-generic path has had: a generic overload set is
  **selected** by its first value argument's type and **mangled** with the resolved declaration's full
  parameter signature, and the definition and the call derive that suffix from the *same* `Decl`, so
  they cannot drift apart. The live consequence: `alloc::hashmap`'s two `iter` overloads of Stdlib
  appendix §2.4 — the map entry point `iter(K, V, ptr(HashMap(K, V)), Arena)` and the Iterator-protocol
  identity `iter(K, V, HashMapIter(K, V))` — can now both be used at the same `(K, V)` in one program.
  Every symbol not in a generic overload set keeps the name it had: the tree contains exactly one such
  set, the compiler never calls it, and the self-host build's assembly is byte-identical. x86_64; the
  three cross backends can neither select nor separate two overloads — measured, they already refuse
  an ordinary non-generic overload set — so a generic overload set is now outside their shape fence
  and they fail loudly instead of answering wrongly; making them correct is tracked as #475.
- The **iterator protocol of `HashMap`** is now reachable through its **qualified** path from outside
  the standard library. Stdlib appendix §6 names `iter` in the closed v1 surface of `HashMap(K, V)`
  and §8.5 makes the §6 alloc-tier types required content given an allocator, with §2.4 fixing the
  protocol as `iter`/`next`; but only the map-**entry** `iter` carried `pub`. The protocol identity
  `iter` and `next` did not, so `alloc::hashmap::iter(u64, u64, ptr(m), a)` — the already-published
  entry point itself — was rejected with `check: invalid`, because the visibility test reports a
  violation when any same-name, same-module declaration is invisible rather than when every candidate
  is. Publishing those two — the only two markers in this change — makes the §6 surface reachable as
  Modules §3 requires. Nothing changes about the map's or the iterator's representation, or about
  iteration semantics, and no call site resolves differently: a program that declares its own `iter`,
  `next` or `Entry` still gets its own, including through `for`. The compiler's own emitted assembly
  is byte-identical. `SplitIter`'s half of the same defect class is not included: the pinned
  specification does not mention `split` at all, and its qualified path is blocked by #455.

- On the **WASM** backend, comparing a struct's **enum-typed field** no longer answers a value that
  matches no variant. Types §6 makes `h.t` read back as the enum the field holds, and §8 delivers an
  enum by reference: on wasm a struct's enum field holds a pointer to the `{disc, payload…}` block,
  the same as an enum parameter. The wat compare arm already refuses to compare such by-reference
  operands with a raw integer equality — that is why `x := Tag.Green ; x == Tag.Green` is a loud trap
  rather than a guess — but its operand test looked at bare names only, so a field read slipped past
  it into the integer path and compared the field's block address against a freshly built literal
  block. Two distinct addresses: `Holder(t = Tag.Green)` reported itself as neither `Red`, `Green`
  nor `Blue`, at exit 0, on a valid module. Both spellings (`h.t == Tag.Green` and `x := h.t` first)
  now take the same fail-loud route as every other enum comparison on wasm. x86_64, aarch64 and
  riscv64 emission is untouched, and the field read itself is unchanged: handing `h.t` to a function
  taking that enum and dispatching there answered correctly before and still does.
- A **diagnostic longer than the driver's message buffer** is now printed, instead of being replaced by
  `rt: StrBuf overflow` and an aborted compiler. Both `alatyr: check:` decoders assembled their message
  into a 256-byte `StrBuf` and the parse decoder into a 1024-byte one, and the runtime's overflow guard
  is a `panic`: measured, the located message printed in full up to **249 bytes** and, at **250**, the
  whole diagnostic was replaced by `rt: StrBuf overflow` — so a user whose program had an error got a
  crashed compiler and no way to know which error it was. The wall was only ~34 characters of module
  name past the longest message in the set, and a module name is a **file name**, so an ordinary
  project's own naming could reach it; the parse message additionally quotes the offending lexeme,
  whose length is bounded only by the source, and a 950-character token was enough to kill the 1024
  buffer the same way; the two manifest renderers had the same wall at 512 and 768 bytes, reachable
  with a deep enough package directory. All six now write their pieces straight to stderr, so there is
  no capacity left to overflow — the same bytes in the same order, with no ceiling (a 20 068-byte
  message prints in full, with the ordinary reject status). Every message that already fitted is
  byte-identical:
  `alatyr check` over all 1 890 tracked `test/*.al` fixtures, 431 of which emit a diagnostic, differs in
  **0**.
- An **assignment to a struct's enum field** (`h.t = v`) is no longer **dropped** on x86_64. Types §6
  makes a struct field hold the enum it was given and an assignment observable at the next read of that
  place, but `mut h := Holder(t = Tag.Red) ; h.t = v` built cleanly, exited normally and read back
  **Red** — the variant the struct *literal* had written — for `v` an enum parameter and for `v` an enum
  local alike. The whole-enum writer matched only a variant *literal*; every other value kind fell into a
  wildcard that emitted **no instruction at all**, so the store simply never happened. That is a dropped
  store, and it is a different defect from the aarch64/riscv64 one fixed just before it, where the store
  did happen but wrote the §8 by-reference block pointer instead of the discriminant. A payload-carrying
  enum lost its payload words the same way, an enum-returning call on the right-hand side was dropped
  too, and so was an enum **variable used as an element of an array literal** (`xs := [e, Tag.Blue]`),
  which reached the same wildcard. All of these now store the complete `{disc, payload…}` block. A
  niche-folded `Option(ptr(T))` and a raw union are untouched — each already has its own writer — and any
  value kind still not handled emits exactly what it emitted before, so nothing that compiled starts
  being refused. x86_64 only: aarch64 and riscv64 refuse this shape fail-loud, and the wasm field read is
  a separate defect. The compiler's own emitted assembly is byte-identical.

- A **field read through a `ptr(str)` parameter** now reads the pointee, instead of answering **0**.
  Stdlib appendix §3.5/§3.6 make `str` the base tier's two-word `{ptr : ptr(u8), len : usize}` pair
  and Memory §4.1 makes `deref(q).len` an ordinary read through the pointer, but
  `probe := fn(q : ptr(str)) -> usize { deref(q).len }` built cleanly and answered **0** for a
  four-byte string; `deref(q).ptr` answered a **null** pointer, and binding the pointee first
  (`ss := deref(q)`) copied one word, so `ss.len` read a neighbouring frame slot. The identical
  shape over a user struct was always correct — `str` and `[T]` simply have no struct declaration,
  so a `ptr(str)` parameter matched no pointer-to-aggregate binding and recorded no pointee at all.
  The visible consequence was in the standard library: `base::str::split(ptr(s), sep)` — its only
  `ptr(str)` entry point — returned a `SplitIter` whose `len` was 0, i.e. an **empty iterator**, so
  `for part in split(ptr(s), 44)` yielded nothing. Both now answer correctly. x86_64 only: aarch64,
  riscv64 and wasm already refused these shapes fail-loud rather than answering the wrong value. The
  compiler's own emitted assembly is byte-identical, and no other program in the tree declares a
  `ptr(str)` parameter.
- A `{}` **template hole holding a negative signed integer** now prints the same text on all four
  backends. Functions §7.1 routes a hole through the scalar rendering layer and Stdlib appendix §2
  fixes that layer's integer form as base-10 with "a leading `-` for a negative two's-complement
  value"; **aarch64**, **riscv64** and **wasm** each had exactly one integer renderer and it was
  unsigned, so `a : i64 = 0 - 128` printed **18446744073709551488** on those three while x86_64
  printed **-128**. The program compiled cleanly and exited 42 on every backend — only the text was
  wrong, which is why the exit-code cross-target sweeps never contradicted it, and why no fixture had:
  every cross-backend stdout row in the suite printed a non-negative number (#444). Each of the three
  template emitters now picks a signed renderer when the hole's static type is signed, using the same
  signedness oracle `/`, `%` and `shr` already route on; a hole that oracle does not prove signed keeps
  the unsigned renderer and its exact previous bytes. The new signed helper is written last and only
  when a signed hole actually reached it, so a program without one emits byte-identical output to
  before — measured over all 1532 of `test/*.al` on all four backends, 0 differing. A hole whose signedness
  that oracle cannot see — an un-annotated local, an array element, a call result — still renders
  unsigned on the three backends; that residual is tracked separately.
- The **code-point iterator** of `str` is now reachable through its **qualified** path from outside
  the standard library. Stdlib appendix §3.6 lists `chars(in self) -> CharIter` as an Iterator (§2.4),
  and §2.4 makes the returned type usable through `iter`/`next`; those two `CharIter` overloads were
  already `pub`, but `base::str::iter(cursor)` and `base::str::next(cursor)` were still rejected with
  `check: invalid`. The cause was the **other** pair of overloads of the same two names in the same
  module: `SplitIter`'s `iter`/`next` were private, and the visibility test reports a violation when
  any same-name, same-module declaration is invisible rather than when every candidate is. Publishing
  the `SplitIter` protocol pair — the only two markers in this change — makes the §3.6 surface
  reachable as Modules §3 requires. Nothing changes about representation, decoding or iteration
  semantics, and no call site resolves differently: a program that declares its own `iter`, `next` or
  `split` still gets its own, including through `for`. The compiler's own emitted assembly is
  byte-identical.
- `alatyr fmt` no longer **deletes the target type** of a `bitcast` it cannot see in the tree.
  `bitcast(T, v)` is the identity on the block whenever `T` is a word-sized scalar, `str`, `type`, or
  a pointer over one of those, so the parser drops the node and every back end stays on the identity
  path — but the formatter reads the same tree, and with no node to read it wrote
  `unchecked bitcast(usize, n)` back to your file as `unchecked (n)`, at exit 0. Tooling §4.3 makes
  `fmt` semantics-preserving and the written target is what types a bare binding, so this quietly
  replaced a conversion with whatever type the operand happened to have; formatting this compiler's
  own sources rewrote about 1 100 such casts. The target span now survives beside the AST and comes
  back verbatim in every position — argument, operand, initializer, postfix base — including two
  erased levels on one expression, and the `unchecked` marker is recovered from the source rather
  than invented. What the compiler emits is unchanged: recording is on only for `fmt`.
- An **expression-form `match` in tail position** over an enum **place** now selects the right arm.
  Control Flow §5.3 makes `match` one expression with one meaning, but the tail-value route resolved
  only two kinds of scrutinee — a plain enum local and a mutable enum global — and sent every other
  enum place to the *integer* compare path, where an enum pattern arm carries no scalar literal at all.
  Every arm therefore compared the scrutinee against **0**, so only a variant whose discriminant is 0
  could ever match: `dotted := fn(h : Holder) -> u64 { match h.t { Red => 32, Green => 64, Blue => 128 } }`
  built cleanly and answered **0** for `Green` and `Blue`, and with a wildcard present it answered the
  wildcard instead. Reordering the arms exposes the other half of the same mechanism — write `Green`
  first and the **first arm** wins for every input. A struct field (`h.t`), an enum-array element
  (`cs[i]`), a struct-field array element (`h.items[i]`), an array-of-struct element's field (`xs[i].t`)
  and a mutable global struct's field (`G.t`) were all affected, and payload bindings through those
  places were lost with them. All five now materialize their enum words exactly as the value-expression
  and braced statement forms already did, which is why binding the field to a local first, or writing
  braced arms, was the workaround. x86_64 only: aarch64, riscv64 and wasm have no enum-match lowering
  and refuse an enum scrutinee fail-loud. A **nested** place (`o.inner.t`) is a separate, still-open
  defect — it answers the same wrong value in *every* match form, including the bound-local one.
- **aarch64 and riscv64** no longer answer the **wildcard** for a `match` over an enum **place**. The
  previous entry's aside — that those two backends have no enum-match lowering — is only half true, and
  the half that is false was the defect. Both do dispatch `match <struct local>.<enum field>` on the
  field's frame words; what was wrong is what the field held. An enum argument is passed **by
  reference**, so an enum parameter's frame slot carries a pointer to the caller's `{discriminant,
  payload…}` block, and the struct-literal field store wrote that slot through as one scalar word — an
  address where the discriminant belongs. Every arm then compared unequal and the wildcard won:
  a function whose body is `h := Holder(t = v)` followed by
  `match h.t { Red => 11, Green => 22, Blue => 33, _ => 91 }`
  built and linked cleanly and answered **91** for every variant, while the same program written with
  the field bound to a local first (`x := h.t`) trapped fail-loud. One spelling loud, the other a wrong
  number. The same one-word store dropped every **payload** word of an enum local wider than one word,
  so a matched arm read its payload out of a slot nothing had written. Both backends now copy the
  enum's full width into the field — through the block pointer for a parameter, whole for a wide local
  — at the struct-literal, struct-return and element-assignment writers alike. x86_64 and wasm are
  untouched, and the spellings neither backend can lower (`match` over a bound local, an array element,
  a struct-field array element or a global's field) still refuse fail-loud, which is the correct
  outcome until they gain a lowering.

- A single-file program that reaches the ambient allocator by its **bare names** now gets the base
  prelude. The shipped stdlib is injected by scanning the source text, and the only text that pulled
  the allocator surface was the bare name of the fallible-result type. Control Flow §5.2 makes a bare
  variant pattern (`Ok(h)`, `OutOfMemory`) exactly as legal as `Result::Ok(h)`, so a program that
  spells its patterns bare could contain no occurrence of that word at all — and then `Arena`,
  `arena_over`, `allocate` and the allocator error enum were all rejected as unbound names on a
  program the specification calls valid. The arena type, its constructor and the error enum are now
  triggers of their own, word-boundary matched, so `ArenaPool` or `AllocErrorKind` does not pull
  anything. A file that declares those names itself keeps its own meanings. This is the residual half
  of the defect first seen as `alatyr fmt` writing source that no longer compiled: the formatter stopped
  respelling patterns earlier, but any tool that rewrites source could still change which prelude a file
  gets, and a program that never needed rewriting was refused outright. Manifest/package builds keep the
  narrower result-name trigger they had.
- The **wasm** backend now answers correctly when a nested block shadows a **parameter**, as
  Declarations §6.1 allows ("an inner scope may shadow an outer name"). Its frame gives one *name* one
  slot for a whole function and its read path resolved a parameter before a local, so the shadow's
  `:=` wrote a slot nobody read: `if p == 1 { p := 8 ; acc = p }` left `acc` holding the argument, and
  the same shadow in a `while` body silently answered **6** where x86_64, aarch64 and riscv64 all
  answered **10** — a wrong value on a clean compile. Entering a block that binds a parameter's name
  now seeds that binding from the parameter and makes the block's reads resolve to it; leaving the
  block puts the parameter back in scope. Reading a bare **scalar parameter** on the right of an `=`
  or a `:=` was a second face of the same defect: a parameter's `: T` annotation was taken for a
  struct name without confirming it named one, so `acc = p` over `p : u64` went to the whole-aggregate
  copy path and **trapped** (134) instead of copying a word. Seven programs that used to trap on wasm
  — `std_math`, `math_ln`, `math_sin`, `math_cos`, `math_sqrt`, `inline_stmt_body` and
  `lambda_capture_comptime_if` — now run and answer what x86_64 answers. x86_64, aarch64 and riscv64
  emit byte-identical assembly before and after. What the outer name means *after* the shadowing block
  ends still differs between wasm (which restores it, per §6.1) and the three native backends (which
  do not); that divergence is tracked separately.
- Indexing an **array field of a mutable module-level struct** — `gg.xs[i]`, read **and** write — is
  now bounds-checked, as Types §6.4 requires by default. The check was missing on exactly this shape,
  on both sides. With `mut gg := G(xs = [10, 20, 30], guard = 99)`, the out-of-range read `gg.xs[3]`
  compiled cleanly and exited **99**: the address math ran past the field and returned the struct's
  *next field* as an ordinary value. The store `gg.xs[3] = 77` was worse in the same way — it
  **overwrote** `guard`, so a later read of `guard` returned the value the program believed it had put
  in the array. Both are silent wrong values, and both are hard to spot precisely because a
  neighbouring field is a plausible-looking number rather than obvious garbage. Every adjacent shape
  was already checked and is unchanged: the same array as a **local** struct's field, a direct mutable
  **global** array (`TABLE[i]`), a by-reference array parameter, a slice and a str. An **immutable**
  module-level struct's array field is a separate, already-loud case: it is refused with a "not yet
  supported" diagnostic and stays refused. `unchecked` still drops the check on exactly these two
  accesses (CT-11 / CG-7), including the address, which is unchanged. x86_64 only, because that is the
  only backend that lowers the shape at all: aarch64, riscv64 and wasm emit a fail-loud `unsupported
  index` trap for `gg.xs[i]` whether the index is in range or not, so they were never affected and are
  untouched here.

- Re-declaring a name **already bound in the same scope** is now a compile error, as Declarations §6.2
  requires ("a name means one thing within its scope"). No surface enforced that for function-body
  locals: `check` accepted the program and the four backends then disagreed. Written with two
  different types (`r := Result(usize, u32).Ok(7)` then `r := Option(usize).Some(9)`), the `match`
  below resolved its arms in the wrong enum and took **no** arm, so x86_64 fell through to the
  fallback and answered `77` on a clean compile — until a lowering-side fence started refusing that
  one spelling; aarch64, riscv64 and wasm trapped at run time instead. Written with the **same** type, all four backends accepted it
  in silence. The refusal is now a located `check` diagnostic naming the second declaration's line, so
  `check`, the `-o` build and the three emit-to-stdout backends refuse it identically and emit
  nothing. Cross-scope shadowing (§6.1) is untouched and stays legal: an inner block may shadow an
  enclosing name or a parameter, two sequential non-overlapping blocks may each bind the same name,
  two sibling `for` bodies may each bind the same loop-local, a `match` arm's payload binding may
  reuse one name across arms, and `x = v` after `x := v` is a write, not a second binding. `_` is a
  discard, not a name, so repeated `_ :=` is unaffected. The one specification exception — function
  overloading by signature (Functions §1.4 / FN-7) — is not reachable today: the lower has no local
  overload set, and no fixture spells one.
- Assigning to an element of a **string literal** is refused where it is written, instead of quietly
  becoming the function's result. `"abc"[0] = 65` followed by a `7` used to build with no diagnostic
  and exit **65**: the line was not recognized as a statement at all, so it fell to the
  trailing-expression path, where the `=` was taken for an opening parenthesis, the `65` for the
  parenthesized expression and the `7` for its closing token. The declared result was never reached
  and nothing said so — a silent wrong value. A literal is a value, not a storage location: its bytes
  are emitted once into read-only data, so a store has nothing to write into (Memory §1.6; Types §7),
  and Grammar §3.3 roots every assignable place at a name, a path or a `deref(…)`. The runtime-index
  spelling `"abc"[i] = v` and the compound `"abc"[0] += 1` were accepted the same way and are refused
  the same way. The refusal is in the parser, so `alatyr check` and all four emission surfaces
  (x86_64, aarch64, riscv64, wasm) agree and none leaves an artifact behind. Reading a literal
  element (`u64("abc"[0])`), writing an array element (`a[i] = v`) and every other place form are
  untouched. Newly rejecting a program the specification declares invalid: the defect was accepting
  it.
- Storing into an element of a **`str`** is refused in `check`, instead of killing the process. This is
  the neighbour of the entry above, and it reached the fault by a different route: here the target
  really is a place — `s` is a name, `s[i]` a legal `place` by Grammar §3.3 — so the parse is correct
  and the parser fence never sees it. `s := "abc"` followed by `s[0] = 65` built with no diagnostic and
  died with **SIGSEGV** (x86_64 exit 139) writing into `.rodata`; aarch64 and riscv64 reached a
  fail-loud trap (133) and wasm aborted (134), so all four backends accepted the program and then gave
  four different answers, none of them a message. `mut` did not help and was not supposed to: `str`
  **is** the slice `[u8]` (Types §7, Stdlib appendix §3.6), a slice's element permission comes from its
  pointer, and the writable spelling is `[mut T]` — so under Memory §3.3's AND rule the `mut` step
  passes and the pointee step fails. `mut s := "abc"` and `mut s : str = "abc"` segfaulted the same way
  and are refused the same way, as is the compound `s[0] += 1`. The refusal is in the shared semantic
  pass, so `alatyr check`, the `-o` build and the three emit-to-stdout backends agree and none leaves
  an artifact. What `mut` does buy is untouched: a whole-view reassignment `mut s := "abc"; s = "de"`
  is still legal. Reading a `str` element, sub-slicing one, `mut` array element writes, `mut` struct
  field writes and `deref(p) = v` are all untouched. An alias is covered too, and had to be: `t := s`
  copies the two-word view and not the bytes, so it inherited the same read-only run, and on the
  parent it re-opened the fault for every spelling of `s` — including a `str` parameter, whose own
  direct `s[i] = v` was already refused, so a one-word edit walked around that refusal. Where the
  FIRST failing step of the path is the binding itself — an immutable `s : str`, a `str` parameter, a module-level `G := "abc"` — the
  established `immutable binding` diagnostic still owns the message, unchanged. Newly rejecting a
  program the specification declares invalid: the defect was accepting it.
- Assigning to **any** value-expression is refused where it is written, closing the rest of the class
  the string-literal entry above fenced one spelling of. `5 = 3`, `f() = 65`, `[1, 2, 3][0] = 65` and
  `bytes(s)[0] = 65` all used to build with no diagnostic; the first exited **3** and the other three
  **65**, in each case the assignment's right-hand side standing in for the declared result. The cause
  is the same one: none of these was recognized as a statement, so the line fell to the
  trailing-expression path, where the `=` was taken for an opening parenthesis, the right-hand side
  for the parenthesized expression — and the **next statement** for its closing token. That last part
  is what makes this worse than an accepted bad program: a line of real work in between simply
  vanished. A program that declares 42 and stores through a live local between the bad assignment and
  the result exited **12**, cleanly, silently. Memory §1.6 is normative — a store's left operand must
  be a place-expression, and assigning to a value-expression is ill-formed — and Grammar §3.3 roots
  every place at a name, a path or a `deref(…)`, which a literal, an array constructor and a call
  result are not. The refusal is in the parser, so `alatyr check` and all four emission surfaces
  (x86_64, aarch64, riscv64, wasm) agree and none leaves an artifact behind. Every legal place form is
  untouched, in both the plain and the compound spelling: an array element, a struct field, an array
  element of a field, a tuple component, a `deref(p)` store and a qualified `mod::G` target. Newly
  rejecting a program the specification declares invalid: the defect was accepting it.

- The unary prefixes `-` and `~` now apply to the element, field or component the source names. Both
  took their operand at the **primary** level, so a postfix step that followed applied to the prefix's
  RESULT: `-a[i]` parsed as `(-a)[i]`, `~a[i]` as `(~a)[i]` and `-p.b` as `(-p).b`, and the read went
  to a frame slot instead of the array or struct. With `xs : [u64; 4] = [71, 42, 93, 55]`,
  `-xs[1]` negated `0` where `42` was due, `~~xs[2]` answered `5` where `93` was due, and nothing said
  so — the frame slot holds whatever that frame keeps, so the wrong answer is not reliably `0` and can
  look entirely plausible. Grammar §3.4 gives the unary level a `postfix-expr` operand and §4 puts the
  whole postfix family (call, index, field, UFCS, `?`) one level TIGHTER than the prefixes, so the
  postfix chain is part of the operand. Every base was affected the same way: a fixed array, a typed
  slice, a struct field, a tuple component and a UFCS chain. Parenthesizing the operand
  (`-(a[i])`) was already correct and is unchanged; parenthesizing the whole expression (`(-a[i])`)
  was **not** a rescue and now needs none. Binary operators are untouched — `~a & b` is still
  `(~a) & b` and `-c % d` is still `(0 - c) % d` — and `not`, which the parser takes at the comparison
  level, already reached past its postfix chain. On aarch64, riscv64 and wasm these shapes used to
  stop loudly rather than answer wrongly; they now run correctly there too. `alatyr fmt` needed no
  change: it already renders the prefix operand bare, and that text now re-parses to the same tree.

- The one-access verification mode `unchecked a[i]` now reads the element it names. The modifier
  bound to the **base** rather than the access, so `unchecked a[i]` parsed as `(unchecked a)[i]` and
  the read went to a frame slot instead of the array: `xs : [u64; 3] = [71, 42, 93]` answered `0`
  where `42` was due, and nothing said so. Every base was affected — a fixed array, a `str` local, a
  typed slice and a `str` literal alike — and `unchecked p.f` was silently taken out of its own scope
  the same way. The braced region form `unchecked { … }` was always correct and is unchanged, which
  is why this survived: the fixtures that exercise unchecked indexing all use it. The emitted code
  for `unchecked a[i]` now differs from the checked `a[i]` by exactly the omitted bounds trap, which
  is all the specification permits it to drop (Types §6.4). `unchecked` still binds looser than every
  binary operator, so `unchecked a[i] - 1` is unchanged. On aarch64, riscv64 and wasm these shapes
  used to stop loudly rather than answer wrongly; the array and slice bases now run there too, and a
  `str` index still stops loudly on all three. `alatyr fmt` follows the new binding: an `unchecked`
  operand used as a postfix base keeps its grouping parens.
- `deref` through a pointer bound from a view's data pointer (`q := s.ptr`, `q := bytes(s).ptr`, or
  the same off a `str`-returning call) now reads **one byte** however much whitespace separates the
  binding's name from its `:=`. The compiler recovered "this local is a `ptr(u8)`" by scanning at
  most 512 bytes forward from the name, so a declaration spelled with more spacing than that still
  compiled cleanly and loaded a full WORD instead: `if deref(q) == 65` took the wrong branch and the
  read ran seven bytes past a short `str`, with no diagnostic and a green `check`. An annotated
  pointer (`q : ptr(u8) = s.ptr`) was already correct. The shape the recovery fires on is otherwise
  unchanged — a struct field holding a `ptr(u8)`, and longer chains such as `a.ptr + k`, keep the
  word-sized load they had.

- Two same-named locals of **different aggregate types** in one function are now **refused with a
  located diagnostic** on x86_64 instead of silently answering the wrong value. A local declared in a
  nested block and then declared again in the enclosing scope under the same name but another enum
  type made the later `match` select **no arm at all** — no trap, no diagnostic, the assigned variable
  kept its pre-`match` value — and the same collision over two struct types made a field read answer
  the wrong word. The backend keys a frame slot by name alone for the whole function and recorded the
  first binding's type, so every later member resolution used it. The program is valid
  (Declarations §6.1) and aarch64, riscv64 and WAT already compile it correctly, so this is a
  backend limitation made loud rather than a rule: rename one of the two locals and the program
  compiles everywhere. One name bound to two instances of one generic enum, to two struct types that
  declare the same members, or to its own type again is unaffected, and a `match` arm's payload
  binding is not touched.

- Raw x86_64/Linux/ELF package entries that name ordinary no-parameter `fn() -> i32` functions now
  receive a generated call/exit wrapper, so the result becomes the process status code and procedures
  exit zero; `@abi(naked)` entries remain programmer-owned. The wrapper is emitted **under the entry
  declaration's own linker symbol** — its exact `@export` when it has one, else its module-derived
  spelling — so the executable's ELF entry address still resolves to the symbol the manifest's `entry`
  names, which is what a linker script or external harness keys on. An entry with no exact `@export`
  gives that spelling up to the wrapper and its body moves to the reserved `__alatyr_raw_entry_body`,
  so calling such an entry from inside the program now runs it as the process entry and exits.
- Indexing a string literal directly (`"abc"[2]`) now reads the byte at that offset. The form
  compiled cleanly and returned the contents of a frame slot instead — `u64("abc"[2])` answered `5`
  where `99` was due, and nothing said so; indexing through a local (`s := "abc"; s[2]`) or through
  `bytes("abc")` was always correct. An out-of-range literal index now traps like every other
  checked index, and taking the **address** of a literal element — which used to hand back a pointer
  into the caller's own frame — is refused with a located diagnostic instead of reading a live
  local. `str` is `[u8]`, so the value is a BYTE and not a code point: `"\xc3\xa9"[0]` is `195`.
  x86_64 only; the aarch64, riscv64 and wasm backends do not lower any `str` index yet and continue
  to stop loudly on all of them.
- `for x in <iterator>` now drives `next` instead of counting the iterable's first two words, so
  `for c in chars(s)` / `for c in s.chars()` walk a string's **code points** and `for part in`
  a `SplitIter` walks its pieces. Every spelling used to compile and run the backing view's BYTE
  length while yielding neither the code points nor the raw bytes — `"Aé€😀"` (4 code points,
  10 bytes) iterated 10 times and answered `65, 152, 0, 78, 0, 0, 0, 0, 0, 0` — and `next` was never
  called. The loop drives a copy, so a named iterator variable is not advanced behind your back, and
  the loop variable carries the payload type. A range, array, slice, `str` view, array global or
  `Vec` keeps the counted loop unchanged. An iterator whose `next` this form cannot yet call — a
  generic `next(K : type, …)`, as `alloc::hashmap::HashMapIter` declares, or a `next` that does not
  return `Option(T)` — is now **refused with a located diagnostic** instead of walked as a slice;
  drive it explicitly. One spelling is still wrong for an unrelated reason: `for c in iter(cur)`
  binds its iterator from an overloaded call, and such a binding is typed from the wrong overload
  (see the open follow-up), so it decodes with the wrong `next`.
- `std::os::env` now reads the complete process environment through the same growable
  `alloc::strbuf` image `std::os::args` uses, so a present variable whose value crosses the staging
  boundary is returned in full instead of appearing absent, and an exhausted allocator or failed read
  traps rather than being folded into `None`.
- `base::str` now publishes the `chars`, `iter`, and `next` functions required to consume the
  specification's `CharIter` protocol from an external package, in the qualified, bare and UFCS
  spellings; its representation and decoding behavior are unchanged, and `char_byte` stays private.
- Packed `[u8; N]` returns now extend to two machine words: a return of `N = 9..16` bytes is carried
  in two registers, indexed both after binding and directly on x86_64 and read directly on AArch64,
  and composes with fixed-array forwarding and fixed-array arguments on x86_64. `N = 1..8` keeps its
  existing one-word ABI, and a fixed-array return shape the compiler does not support is now refused
  with a located shape-specific diagnostic instead of falling through to scalar lowering.
- An equal-width aggregate `bitcast` used directly as a by-value struct ARGUMENT
  (`consume(bitcast(B, a))`) now passes the source aggregate's own block on x86_64 instead of passing
  its first word as a scalar, which the callee dereferenced as the block address — the reproducer
  died with a segmentation fault. An unequal bit width or a non-variable source in that position is
  rejected with a located diagnostic, and unsupported non-x86 aggregate bitcasts stay fail-loud.
- `alatyr fmt` now keeps the qualifier an enum-variant pattern was written with: `Result::Ok(h)` and
  `AllocError.OutOfMemory` come back qualified in both the expression- and statement-form arm
  renderers, instead of as a bare `Ok(h)` / `OutOfMemory`; a pattern written bare stays bare. The
  de-qualified text could stop compiling outright — the ambient standard-library prelude is injected
  by scanning the source for a bare `Result`, so deleting a file's last qualified spelling took
  `Arena`, `allocate` and `AllocError` out of scope while `fmt` still exited 0.
- `alloc::string::push` and `alloc::string::push_str` now report the **new byte length** of the
  string in their `Ok` arm, as the Stdlib appendix requires, instead of the number of bytes they
  appended: appending a 1-byte `char` to a 2-byte string answers `Ok(3)`, not `Ok(1)`, and
  `push_str("")` answers the unchanged length rather than `Ok(0)`. `AllocError` propagation and
  `alloc::strbuf`'s own appended-count convention are unchanged.
- A parenthesized generic type instance now works as a `bitcast` target: `unchecked bitcast(Box(P), p)`
  keeps the instantiated layout of `Box(P)` and moves the whole equal-width image on x86_64, instead of
  erasing the target so that every field of the bound local read zero. `alatyr fmt` keeps the type-arg
  group of such a target. Unsupported non-x86 aggregate bitcasts stay fail-loud.
- `alloc::vec::reserve` now returns `Err(AllocError.SizeTooLarge)` for a request it cannot represent
  in `usize` instead of aborting the process: the requested count `len + additional`, the capacity
  doubling, and the byte size handed to `allocate` are each computed with an explicit wraparound
  test. A wrapped count previously would have reported success for a request larger than the address
  space; a successful reserve, a no-op reserve, and a representable `OutOfMemory` are unchanged.
- `Arena.allocate` now returns `Err(AllocError.BadAlignment)` for an invalid alignment instead of
  accepting it: a non-power-of-two `align` used to produce a misaligned `Ok(Handle)` and `align = 0`
  trapped on a modulo by zero before any `Result` existed. A rejection leaves the bump cursor
  untouched; valid powers of two and the `OutOfMemory` path are unchanged.
- AArch64, RISC-V64 and WebAssembly no longer destroy the neighbouring narrow field when a field of a
  fixed-array element held in a struct field is written: the array literal is materialized at the
  element's byte-precise layout instead of one machine word per field. x86_64 was already correct.
- `HashMap(str, V)` now compiles and keys by string CONTENT: the structural `hash` derive gained the
  `Str` case it was missing (it fell through to a scalar conversion and refused the two-word view), and
  a `str` key parameter inside a monomorphized container instance now resolves its comptime type
  argument instead of being rejected. Equal-content views in distinct allocations are one key, through
  `insert`/`get`/`contains`/`remove` and across a rehash.
- AArch64 now emits module-qualified labels for named non-generic functions and direct qualified calls while preserving exact `@extern`/`@export` symbols.
- Aggregate bitcasts now reject packed records with unequal exact byte widths instead of accepting representations that only share a rounded machine-word count.
- Equal-width enum-to-enum `bitcast` bound to a local now preserves the discriminant and every
  payload word on x86_64 instead of copying the discriminant alone over a zeroed payload; unequal
  bit widths and non-variable sources are rejected with a located diagnostic.
- Aggregate `Slice(T)` parameter recovery now uses the complete source buffer instead of a fixed
  512-byte lookahead, so valid aggregate Slice field access beyond that boundary is recovered on
  x86_64 while unsupported non-x86 aggregate lowering remains fail-loud.
- `Result`/`Option` values can no longer be implicitly treated as their payload in explicitly
  annotated local bindings; invalid direct and inferred-local assignments now fail with located diagnostics.
- Semantic checking now rejects a wrong-typed value assigned through a fixed array of structs held in a struct field; deeper and pointer/slice-derived place paths remain separate work.
- Fixed runtime comparison conditions for materialized typed `comptime` `u64` locals so high-bit values
  use unsigned ordering while signed `i64` and ordinary runtime `u64` comparisons retain their paths.
- Fixed closed `comptime if` comparisons over typed high-bit `u64` values so branch selection uses
  unsigned ordering while signed `i64` controls retain signed ordering.
- Duplicate enum discriminants are now rejected by `check` on every target, instead of only by the
  x86_64 lower — the three non-x86 backends previously accepted and ran such a program.
- `CharIter` now bounds-checks its backing view in checked mode and rejects malformed UTF-8 instead of reading past the view or producing an out-of-range code point.
- Direct nested fixed-array parameters are now rejected with one located diagnostic before their malformed parameter ABI can reach lowering; full nested-array parameter support remains a follow-up.
- Fixed x86_64 silent wrong values when an inferred pointer's pointee type lies beyond the old
  512-byte source-recovery window; the scan is now bounded by the actual source-buffer length.
- Direct equal-width aggregate bitcasts used as small struct return values now preserve the source
  words instead of silently returning zero values on x86_64.
- `std::os::args` now reads the complete NUL-separated process command line, growing its arena-backed
  buffer instead of silently dropping arguments beyond the initial 64 KiB chunk.
- Unsupported `comptime if` codegen rejections now retain their source location through transparent `unchecked` conditions in multi-file builds without changing rejection semantics.
- Direct struct-field and explicitly typed local fixed-array-element assignments now enforce the
  declared destination type, rejecting silent `str`/`bool`-to-integer stores with located diagnostics.
- Direct user-defined brands now retain their nominal identity during semantic type resolution, so
  distinct brands with the same underlying layout are not treated as the same semantic type.
- `alatyr build --verbose` / `-v` now reports the selected manifest, profile, target, modules, and
  assemble/link outputs on stderr without changing the build artifact or machine-readable stdout.
- x86_64/Linux/ELF package targets with `Kind.shared_lib` now build a `lib<base>.so` artifact with
  the package's `pub`/`@export` surface and no executable entry point.
- Multi-target `plan` and `build --plan --target all` now emit one deterministic, target-qualified
  `plan.tsv` beside each selected target's artifacts.
- Direct builtin scalar conversions of named user aggregates without an in-scope `@convert` now
  fail at compile time with a located diagnostic on every backend instead of emitting an invalid
  aggregate-as-scalar conversion.
- Direct builtin scalar conversions of exact two-word tuple locals without an in-scope `@convert` now
  fail at compile time with the same located diagnostic instead of silently reading tuple word zero.
- The shared `ast` source recovery (assignment form, compound operator, declared type, no-initializer
  form) and the parser's no-initializer twin now scan to the published source extent instead of a
  fixed 512-byte window past the name. An assignment separated from its operator by a longer
  whitespace run stays an assignment for `sema`, `lower` and `fmt` alike and formatting preserves all
  eight compound spellings; a typed no-initializer local keeps its declared type, so a fixed-array
  local no longer collapses to one scalar word and read the wrong element; and a long declaration no
  longer absorbs the following statement or refuses the file. Every read in that recovery is
  bounds-checked against the source buffer instead of relying on allocator zero-fill.
- `alatyr build --quiet` / `-q` now suppresses the optional success summary while preserving the
  artifact, stdout, and exit status.
- Successful manifest-driven builds now print a deterministic profile, target and artifact summary to
  stderr while leaving stdout available for machine-readable output.
- The bounded scalar `comptime` binding slice now supports closed integer, boolean, and nullary
  user-enum values, while runtime-dependent initializers and unsafe rebinding cases fail loudly.
- WAT now materializes the bounded local scalar `comptime` slice, including literal values and
  `comptime if` conditions, instead of trapping on those programs.
- Unrecognised CLI commands and flags now produce invocation-level Config diagnostics naming the
  offending argument instead of a missing-source-file failure.
- Package setup failures now produce located Config diagnostics: `new` reports an occupied destination
  or missing name, and an explicitly empty `Package.source_dir` is rejected before codegen or linking.
- x86_64/Linux now supports direct code-point `jmp(label)` transfers to named `@label(name)` instructions inside `unchecked` scopes.
- The compiler now reports a controlled arena-initialization failure when an internal `mmap` fails,
  instead of dereferencing the kernel's negative errno result.
- `std::os::arena` now returns `Result(OsArena, IoError)` and maps zero-length and failed
  `mmap` requests before constructing an owning pointer.
- `alatyr fmt` now preserves bare `comptime match` expression arms and keeps the formatted source
  idempotent.
- `alatyr fmt` now preserves multi-segment qualified function return types and their following bodies.
- Ordinary source can no longer construct manifest-only `Package` or `Target` values; `check` and
  `build` now reject them with a located diagnostic.
- Fully comptime-known checked overflow in a direct scalar call argument now produces a located
  compile-time diagnostic before emission instead of compiling and trapping at runtime.
- Fully comptime-known checked overflow in an explicitly typed fixed-array element now produces a
  located compile-time diagnostic before emission instead of compiling and trapping at runtime.
- Declaration-level `when` guards now fold the selected package's `target.kind` and `target.code_size`
  consistently in `check` and `build`, excluding inactive duplicate declarations before name resolution.
- `alatyr fmt` now preserves and canonically emits valid `embed("path")` expressions without
  changing the embedded file bytes.
- Direct multidimensional fixed-array fields now fail loudly with a located diagnostic instead of
  compiling to a wrong value on nested indexing.
- Qualified reads of private module constants now report a located visibility diagnostic instead of
  the generic `invalid` message.
- `check` now agrees with `build` when rejecting direct multidimensional fixed-array fields.
- Unified sub-word scalar-width classification across parsing, formatting, lower layout, and WAT so
  `bits8`/`bits16`/`bits32` pointer casts preserve their intended width and format safely.
- Fixed silent wrong values when equal-width bitcasts target narrow signed, unsigned, or raw scalar
  types by preserving their low-width representation and canonicalizing the machine word on every
  backend.
- The pointee of a `ptr( [mut] T )` bitcast target is now recovered by one bounded, spacing-tolerant
  parse shared by every backend, so the permitted token spacing inside `ptr( … )` no longer widens a
  sub-word `deref` to a full machine word; the generic type-argument scan that feeds it is bounded by
  the published source extent instead of running past the buffer.
- Fixed ordinary scalar-field structs to use natural byte alignment, padding, and field offsets instead of one machine word per field.
- Fixed x86_64 silent wrong values when indexing arrays of narrow scalar structs by sharing the byte stride between literal initialization and indexed places.
- Fixed x86_64 wrong values when indexing a byte slice stored in a struct field by preserving its byte stride and data pointer.
- Fixed x86_64 silent wrong values when reading narrow fields through `Slice(struct)` elements.
- Fixed public `Option` helpers for niche-folded `Option(ptr(T))` values so they inspect the
  pointer-width representation instead of a two-word discriminant/payload layout.
- Fixed niche-folded `Option(ptr(str))` matches so payload bindings retain the pointee's two-word
  `str` view metadata.
- Fixed `run` so profile-looking program arguments after `--` cannot change the selected build profile.
- Fixed silent wrong values when indexing an ordinary byte array through a pointer-derived struct
  field on x86_64.
- Fixed x86_64 wrong matches and aggregate-call crashes for enum elements selected from struct array
  fields; unsupported pointer-derived and packed/byte-layout roots remain fail-loud.
- Statically known out-of-range indexes into fixed arrays now reject at compile time, including every
  index into `[T; 0]`, before any backend emits code.
- Made unsupported live `str`/view operands fail loudly instead of silently becoming an empty pair.
- Package targets with a non-default entry now reject unresolved declaration paths before invoking the linker.
- Made non-x86 entry exclusion explicit so backend wrappers cannot collide with a source `_start`.
- Fixed path dependencies whose source tree contains `lib/`: their modules now retain the dependency
  alias instead of being mistaken for ambient standard-library modules.
- Fixed qualified function-value aliases through nested module paths so direct calls resolve to the
  defining function instead of an undefined importing-module symbol.
- One-element listed projections after a bare module alias now parse as module imports.
- AArch64 now supports scalar nested field access through inferred homogeneous struct-array locals
  with runtime indices.
- RV64 now passes monomorphized `Slice(u64)` views to generic indexed writes without trapping.
- AArch64 now supports whole aggregate-element writes through inferred homogeneous struct-array locals
  with runtime indices.
- AArch64 and RV64 now compare concrete payload-less enum locals with `==` and `!=`.
- WAT now supports labeled `continue name` across statement-only `loop`, `while`, and `for` targets,
  including deferred cleanup for loops crossed by the transfer.
- WAT now supports `continue name` to a scalar-integer value-bearing `@label(name) loop`, including
  LIFO deferred cleanup across nested statement-only loops; unsupported value-loop result shapes remain
  fail-loud.
- WAT now rejects aggregate comptime-field projections loudly instead of loading an aggregate address
  as a scalar value.
- Explicit standard-byte tuple globals now reject before backend emission with a located diagnostic
  instead of reaching the unsupported word-based global representation.
- Immutable module-level aggregate initializers that call at runtime now reject before backend emission
  with a located diagnostic instead of silently becoming zero-initialized static storage.
- Undeclared bare type names used by package nested-module type builtins now reject with a located
  diagnostic before backend emission instead of silently producing a wrong layout-dependent value.
- Unknown bare nominal types in function signatures now reject with a located diagnostic before
  body checking or backend emission instead of silently taking scalar layout and ABI.
- Sema diagnostics for unbound names in compound expressions now report the offending expression's
  line instead of the enclosing declaration's line.
- Indexing a `str` element of a fixed `[str; N]` array (`arr[k][j]`) now reads the byte at offset `j`
  of the selected element. The form compiled cleanly and returned a word of the frame prologue
  instead: the result depended on neither the array, the outer index, nor the string bytes, so
  `arr[0][j]` and `arr[1][j]` were byte-identical and `["abc", "XYZ"]` answered `5` for both
  `arr[0][2]` and `arr[1][2]` where `99` and `90` were due. The same read through a typed
  `Slice(str)` view (`s[k][j]`) is fixed with it, a non-constant outer or inner index works, and an
  out-of-range byte index now traps against that element's runtime length like every other checked
  index. `str` is `[u8]`, so the value is a BYTE, not a code point. x86_64 only; aarch64, riscv64 and
  wasm do not lower this shape and continue to stop loudly on it. Indexing a string LITERAL directly
  is a separate defect and is unchanged here.

First public release in preparation. Nothing is tagged yet; the entries below start once it is.

Entries are added by the change that causes them, in its own commit — not gathered from the log at
release time, which is archaeology and gets the "would a user notice this" judgement wrong once the
measurement is a month old. `CONTRIBUTING.md` states it as a rule and the pull-request template
carries the box.

Where the current state actually stands is the open
[issues](https://github.com/alatyr-programming-language/compiler/issues), honestly and in detail —
including the open silent-wrong-value classes, the cross-backend coverage numbers, and what "ready"
would still require. Read those rather than inferring status from this file's emptiness.
