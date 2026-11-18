- A whole-value assignment `p = v` to an `out` / `in out` struct or enum parameter now reaches the
  caller's place on every backend (#1633; Functions §2.1, §2.3, §4.1): the shared IR builds it, as the
  value in its own object copied whole through the caller's address, so such a function no longer
  refuses to build. The legacy emitters still refuse it (`alatyr x86-legacy`).
