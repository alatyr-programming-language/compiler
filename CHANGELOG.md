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

- Unified sub-word scalar-width classification across parsing, formatting, lower layout, and WAT so
  `bits8`/`bits16`/`bits32` pointer casts preserve their intended width and format safely.
- Fixed `run` so profile-looking program arguments after `--` cannot change the selected build profile.
- Fixed silent wrong values when indexing an ordinary byte array through a pointer-derived struct
  field on x86_64.
- Statically known out-of-range indexes into fixed arrays now reject at compile time, including every
  index into `[T; 0]`, before any backend emits code.
- Made unsupported live `str`/view operands fail loudly instead of silently becoming an empty pair.
- Made non-x86 entry exclusion explicit so backend wrappers cannot collide with a source `_start`.
- Fixed path dependencies whose source tree contains `lib/`: their modules now retain the dependency
  alias instead of being mistaken for ambient standard-library modules.
- Fixed qualified function-value aliases through nested module paths so direct calls resolve to the
  defining function instead of an undefined importing-module symbol.
- One-element listed projections after a bare module alias now parse as module imports.
- AArch64 now supports scalar nested field access through inferred homogeneous struct-array locals
  with runtime indices.
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

First public release in preparation. Nothing is tagged yet; the entries below start once it is.

Entries are added by the change that causes them, in its own commit — not gathered from the log at
release time, which is archaeology and gets the "would a user notice this" judgement wrong once the
measurement is a month old. `CONTRIBUTING.md` states it as a rule and the pull-request template
carries the box.

Where the current state actually stands is the open
[issues](https://github.com/alatyr-programming-language/compiler/issues), honestly and in detail —
including the open silent-wrong-value classes, the cross-backend coverage numbers, and what "ready"
would still require. Read those rather than inferring status from this file's emptiness.
