- `check` now refuses an immutable place bound to an `out` / `in out` parameter — newly rejecting
  programs the specification declares invalid (Functions §2.3, Memory §3.1/§3.3/§3.4), so this is a
  patch. An immutable local, an `in` parameter handed on, a literal, a field of an immutable struct,
  an immutable fixed array, an element of an immutable array and an immutable module global were all
  accepted there, and the callee wrote through them; the direct store `x = v` / `x[i] = v` /
  `s.f = v` already answered `check: immutable binding`, and this route now asks that same question of
  the same root. A `mut` local, an `in out` parameter re-passed, a whole `mut` array and the UFCS
  receiver keep compiling. A **generic** callee is not judged at all, so a call to one — including
  most of `lib/`, whose place-parameter APIs are generic (`Vec`, `Deque`, the `fmt` writers) — stays
  open; the non-generic ones (`StrBuf`'s eight `in out s : StrBuf` methods) are covered. That
  residual, and `ptr(mut …)` over an immutable place, whose rule spec#152 has now settled in favour
  of `ptr(store)` but whose fence lands with the pin, are tracked on #1663.
