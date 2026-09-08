## e2e — Issue #299 / #562, the identity reminder the refusal owes. `resolve_ty` records a Types §8.1
## validity contract `Name := @require(pred) U` with the SAME nominal marker as a §5.4
## `Name := brand(U)` — a non-fn declaration of kind 0 and arity 1 with a return-type span — so both
## come back as the same tag. #561's census measured the consequence: 22 crossings across 18 tracked
## fixtures were attributed brand identity while being `@require` declarations, until the instrument
## learned to read the declaration's source spelling.
##
## §8.1 says a contract's identity is its OWN and is composed differently from a brand's: `R` is
## "identified by the immediate underlying type `U`, the identity of `pred`, and every comptime
## capture value specializing `pred`", where a brand's is the underlying type plus its declared name.
## So two contracts over one `U` with DIFFERENT predicates are different types, and neither converts
## implicitly to bare `U` (§4.3). Both crossings below are therefore invalid — and both are ACCEPTED
## today, which is #562, an open defect that this unit deliberately does not fix.
##
## What this fixture proves is the boundary: the #299 refusal reads the source spelling
## (`sema_brand_is_decl`) before it judges anything, so it does NOT apply brand rules to a `@require`
## type. Without that gate these two functions would be refused by the WRONG rule and the 18
## `require_*`/`fmt_decl_*` fixtures would move with them — "no verdict" replaced by a wrong verdict.
##
## Check-only by construction: no `@require` value is CONSTRUCTED here, so no checked-predicate trap
## is emitted and the program says nothing about the x86-only require-trap surface. When #562 lands,
## THIS FIXTURE MUST FAIL and move to a `reject_*` row.
is_nonzero := fn(v : u64) -> bool { return v != 0 }
is_pos := fn(v : u64) -> bool { return v > 0 }

NonZero := @require(is_nonzero) u64
Positive := @require(is_pos) u64

take_nz := fn(x : NonZero) -> u64 { return u64(x) }

## §8.1: `Positive` and `NonZero` are distinct types. Accepted today (#562).
cross_contract := fn(p : Positive) -> u64 { return take_nz(p) }

## §4.3: bare `u64` into a contract sink needs the explicit constructor. Accepted today (#562).
raw_into_contract := fn(r : u64) -> u64 { return take_nz(r) }

main := fn() -> u64 { return 42 }
