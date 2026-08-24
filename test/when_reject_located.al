## e2e (check_located) — a generic `when size(T)` PREDICATE that folds FALSE is now rejected at CHECK time
## with a SOURCE-LOCATED diagnostic (D69/CT-4/CT-5), not a bare undefined-symbol LINK error. `pick(T, x)`
## is guarded `when size(T) <= 8`; instantiated with `Big` (a 3-word struct, size 24 > 8) the guard folds
## FALSE, so the instance `pick__Big` is AS-IF-ABSENT. `check` REJECTS the call and LOCATES it at the call
## site (line 12) — a faithful sema mirror of `lower::guard_fold_inst`'s size-predicate fold. Before this,
## `check` accepted (the false instance surfaced only as an undefined symbol at LINK).
Big := struct { a : u64, b : u64, c : u64 }

pick := fn(T : type, x : u64) -> u64 when size(T) <= 8 { x }

main := fn() -> u64 {
  pick(Big, 42)
}
