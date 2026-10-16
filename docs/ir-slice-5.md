# IR slice 5 — brands and conversions

Slice 5 of `docs/ir.md` §7.2: brand constructors with their `@require` checks, `@convert`, bitcast to
aggregates. It lands in steps, each its own PR through the full gate (D8).

## 1. 5a — brands and required types (as built)

- **Representation.** A brand `Id := brand(U)` and a required type `R := @require(pred) U` have their
  underlying type's exact runtime representation (Types §4.4, §8.1). In a signature — a parameter, a
  result, an argument's parameter — such a type over a kernel scalar is that scalar
  (`ib_type_ks`, following `lower_layout::brand_underlying` to a bounded depth). Every value inside a
  function keeps sema's record of it, as before, so a brand value is built exactly where sema typed it.
- **Construction.** `B(v)` with one argument, where `B` is a brand or required type and no function is
  named `B`: `v` is built at the immediate underlying scalar `U` (assignable to `U`; a value of another
  brand is not, and stays `NotYet`), and the construction's value is `v`. For a required type the
  explicit gate of §8.1 follows: the predicate is called with `v` and a false answer traps `require`
  (`trap_if`, located at the construction). The predicate must be the one non-generic function of its
  name with one `U` parameter returning `bool`; otherwise the construction is `NotYet`.
- **Sema's records (D6).** The builder takes every value type from sema, so two gaps were closed there,
  in the value-type channel only (the brand IDENTITY checks are untouched): a required type's value type
  is its underlying scalar's (`sema_vty_name`; `sema_brand_underlying` keeps answering `brand(…)` alone),
  a `B(v)` construction's argument takes `U` as its literal context, and the construction itself is
  recorded at `U` (`sema_vty_call`). x86_64's emission does not move: fixpoint holds with no promotion.
- **Back to the underlying type.** `u64(x)` of a brand value is the ordinary scalar conversion: the value
  already has the underlying representation.
- **Outside 5a** (`NotYet`): `@convert` dispatch (5b), a brand over a brand or over an aggregate, a
  required type whose gate is the UFCS spelling of a generic predicate, and `@require` on aggregates.

### 1.1 Measured (omen, before the gate)

`corpus_manifest --check` against `main`: 9 rows move, each from a trap to the x86_64 value —
`require_ok`, `require_ufcs_ok` and `accept_brand_explicit_conversions` on aarch64, riscv64 (run/133 →
42) and wasm (run/134 → 42) — plus the four rows of `test/ir_brand.al` (42 on all four backends, every
function `Built`). No x86_64 row moves; seed == Stage1 == Stage2.
