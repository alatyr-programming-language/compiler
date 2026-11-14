- **A module constant declared as a pair of `when` alternatives has exactly one declaration on the
  target, in `check` and in `alatyr ir` (#1577).** A declaration whose guard folds false is absent
  (Comptime §7.1, §9.2), but sema's name pick still counted it. The two alternatives tied and the
  name went untyped, and the `ir` verb, unlike the emitters, did not fold the guards before its prune.
  So every function reading such a name, `std::sysno::MMAP` among them, was refused by the IR. Sema's
  pick now skips the absent declaration, and the `ir` verb folds the guards as the emitters do. A side
  effect: `check` now types such a name, so `bonus := 0 when …` is an `i64` (Types §9.1). Mixing it
  with an unsigned operand without a conversion is now refused, as it already was for an unguarded
  `bonus := 0`.
