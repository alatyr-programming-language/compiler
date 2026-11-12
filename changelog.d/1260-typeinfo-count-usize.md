- **A `comptime for` bound that subtracts past zero from a `typeinfo` member count is refused (#1260).**
  `comptime for i in 0 .. typeinfo(P).fields.len - 4` with three fields unrolled **zero** times and the
  program ran on, answering 40 where a diagnostic was due. `typeinfo(P).fields` is `[Field]` and a
  slice's `len` is `usize` (Stdlib appendix), so `3 - 4` is a checked unsigned subtraction that
  overflows, and Comptime §2.6 makes a checked operation that fails during comptime evaluation a located
  compile-time diagnostic that never materializes a wrapped value. Sema recorded no type for the member
  count, so the range-bound folder could not judge the operation and folded `-1` as a signed word. Sema
  now records `usize` for `typeinfo(T).n` and for the `len` of `typeinfo(T).fields` and
  `typeinfo(T).variants`, and the folder judges the bound through it. The program is refused with
  `this range bound overflows its type … at line 11`; spell the wrap `unchecked (…)` to get it.
  Measured: on `main` the fixture compiles and answers 40; with the fix it is refused, while the
  in-range controls (`0 .. typeinfo(P).fields.len - 1` unrolling twice, `0 .. typeinfo(P).fields.len`
  three times, and an array instance's `typeinfo(T).n - 1` twice) answer 42 on both trees — a guard
  that fired there would be a wrong reject. The `unchecked (typeinfo(P).fields.len - 4)` spelling folds
  to the wrapped 2^64 − 1 and is refused by the unroll budget (Comptime §2.2); on `main` it too unrolled
  zero times and answered 40. Sema types exactly these two shapes: `n` read directly on `typeinfo(T)`,
  and `len` of its `fields` / `variants` table.
