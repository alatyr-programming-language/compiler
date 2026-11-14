- **A module constant declared as a pair of `when` alternatives has exactly one declaration on the
  target, in `check` and in the IR (#1577).** A declaration whose guard folds false is absent
  (Comptime §7.1, §9.2), but sema's name pick and the IR builder's both still counted it. The two
  alternatives tied, the name went untyped, and every function reading it, such as a reader of
  `std::sysno::MMAP`, fell back from the IR to the legacy emitter. Both picks now skip the absent
  declaration. A side effect: `check` now types such a name, so `bonus := 0 when …` is an `i64`
  (Types §9.1), and mixing it with an unsigned operand without a conversion is refused, as it already
  was for an unguarded `bonus := 0`.
