# Changelog

What a *user of the toolchain* would notice. The full record of how the compiler got here is its git
history and `seed/VERSION`; this file is the short version, aimed at someone deciding whether a new
build changes anything for them.

## Versioning policy

The compiler is versioned independently of the specification, and it **cites** the spec revision it
conforms to. Those two numbers move for different reasons and must not be conflated: a spec revision
can land without any compiler change, and the compiler changes constantly without the language
moving at all.

- **MAJOR** — a program that used to compile no longer does, or produces a different result. Also:
  the spec revision this build conforms to moves by a major.
- **MINOR** — new surface: a construct that used to be rejected now works, a backend gains a shape,
  a CLI verb or flag appears.
- **PATCH** — a defect fixed with no new surface, or a diagnostic improved. A **silent wrong value**
  turned into a correct one, or into a loud failure, is a PATCH even though its effect on a program
  can be dramatic; that is the class this project treats as most urgent.

Two things that deliberately do **not** move the version: making an existing rejection *louder* or
better-located (the program was already refused), and any change under `scripts/` — the gates are
how this repository proves itself, not part of what it ships.

## Unreleased

- The bounded scalar `comptime` binding slice now supports closed integer, boolean, and nullary
  user-enum values, while runtime-dependent initializers and unsafe rebinding cases fail loudly.
- Unrecognised CLI commands and flags now produce invocation-level Config diagnostics naming the
  offending argument instead of a missing-source-file failure.
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
