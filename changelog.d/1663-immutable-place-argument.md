- `check` now refuses an immutable place bound to an `out` / `in out` parameter — newly rejecting
  programs the specification declares invalid (Functions §2.3, Memory §3.1/§3.3/§3.4), so this is a
  patch. An immutable local, an `in` parameter handed on, a literal, a field of an immutable struct
  and an immutable fixed array were all accepted there, and the callee wrote through them; the direct
  store `x = v` / `x[i] = v` / `s.f = v` already answered `check: immutable binding`, and this route
  now asks that same question of the same root, so the two cannot drift on it. A `mut` local, an
  `in out` parameter re-passed, a whole `mut` array and the UFCS receiver keep compiling. Calls to a
  **generic** callee are not yet judged — every `lib/` place-parameter API is generic, so those sites
  stay open and are tracked on #1663, together with `ptr(mut …)` over an immutable place, whose rule
  spec#152 has not settled.
