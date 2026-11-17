- **x86_64: a negative narrow signed payload no longer reaches a legacy caller zero-extended (#1726).**
  A function built by the shared IR wrote an `i8`, `i16` or `i32` enum payload component at its own
  width into a zeroed word, so a legacy-emitted caller read `Result(i32, u64).Ok(-12345)` as
  `4294954951`. The builder now writes such a component as its whole canonical word, sign-extended,
  in a variant literal and in `?`'s error pass-through.
