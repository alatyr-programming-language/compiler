- `check` refuses an immutable place bound to an `out` / `in out` parameter, and `ptr(mut …)` taken to
  a place whose write path is not writable (Functions §2.3, Memory §3.1/§3.3/§3.4/§4.4). An immutable
  local, an `in` parameter handed on, a literal, a field of an immutable struct and an immutable fixed
  array were all accepted there, and the callee or the pointer then wrote through them; the direct store
  `x = v` / `x[i] = v` / `s.f = v` already answered `check: immutable binding`, and both routes now ask
  that same question, so the three cannot drift. A `mut` local, an `in out` parameter re-passed, a `mut`
  global, an element of a `mut` array and the UFCS receiver keep compiling, as does the read-only
  `ptr(x)` of an immutable place.
