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
`current-seed-version` in `seed/VERSION`'s CURRENT SEED block. It fires on both ways of breaking it — a
promotion that forgets the bump, and a bump made without a promotion. The fixpoint itself would not
catch either: the version IS part of the emission (a compile-time constant, TOOL-21), but changing it
moves the seed's output and Stage1's identically, so they stay byte-equal.

A promotion commit therefore carries all of these, and the gate is red if any is missing:

1. `seed/alatyr` — the promoted Stage2 binary.
2. `seed/VERSION` — the appended entry with the three stage hashes and the **read** delta, plus the
   CURRENT SEED block updated to the new hash and version. The entry is the reviewable part: it lands
   in the promotion PR, where a human can read the delta before it becomes history.
3. `package.al` — the new `version`.
4. `scripts/package_cli_test.sh` — its expected `alatyr <version>` line. Easy to forget, and forgetting
   it fails the gate with a diagnostic that never mentions the version.
5. This file — `## Unreleased` becomes `## <version> — <date>`, and a fresh empty `## Unreleased`
   opens above it.

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

- A parenthesized generic type instance now works as a `bitcast` target: `unchecked bitcast(Box(P), p)`
  keeps the instantiated layout of `Box(P)` and moves the whole equal-width image on x86_64, instead of
  erasing the target so that every field of the bound local read zero. `alatyr fmt` keeps the type-arg
  group of such a target. Unsupported non-x86 aggregate bitcasts stay fail-loud.
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

First public release in preparation. Nothing is tagged yet; the entries below start once it is.

Entries are added by the change that causes them, in its own commit — not gathered from the log at
release time, which is archaeology and gets the "would a user notice this" judgement wrong once the
measurement is a month old. `CONTRIBUTING.md` states it as a rule and the pull-request template
carries the box.

Where the current state actually stands is the open
[issues](https://github.com/alatyr-programming-language/compiler/issues), honestly and in detail —
including the open silent-wrong-value classes, the cross-backend coverage numbers, and what "ready"
would still require. Read those rather than inferring status from this file's emptiness.
