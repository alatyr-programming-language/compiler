## Issue #510, the over-eagerness half — the fix for a discarded expression statement must discard
## its VALUE, not its EVALUATION, and must not touch the tail-expression position it is gated on.
## `drop` in WASM pops a value that has already been computed; an emission that instead skipped the
## statement would silently lose a real side effect, which is a worse defect than the one being
## fixed.
##
## Measured on the parent (`origin/main` 71ea8df) and on the fix, each shape as its own `main`,
## `alatyr wat` + `wat2wasm` + `wasmtime -C cache=n` for the wasm column:
##
##   shape                                 parent x86/a64/rv64  parent wasm  fixed wasm
##   discarded effect call, tail reads it            42               12          42
##   the same global observed from `main`            42               42          42
##   the same expression IN tail position             8                8           8
##
## `bump` returns its ARGUMENT, not the counter, so the discarded call's value (12) can never alias
## the answer the tail is supposed to deliver (42). That is what made the parent's wasm column
## readable: 12 is the leaked statement value and nothing else produces it.
##
## The second row is the effect proof from outside the function: `CTR` must be 30 + 12 whichever
## backend ran, so both `bump` calls must have EXECUTED — a fix that elided the trailing statement
## would leave 30. The third row is the tail-delivery proof: `q + 1` written as the fn's trailing
## expression must still be the result, since the fix changes a flag that governs exactly that
## position.
##
## Registered with `run` (so the a64/rv64/wasm sweeps execute it) plus an explicit `run_wat` row.
## Codes from 110, distinct and below 126.

mut CTR : u64 = 0

## Returns its argument while mutating the module global — the value and the effect are different
## numbers on purpose.
bump := fn(n : u64) -> u64 {
  CTR = CTR + n
  n
}

## Two effecting calls in statement position; the second one is the trailing statement, which is the
## position the fix changes. The tail expression reads the accumulated effect.
discard_effect := fn() -> u64 {
  bump(30)
  bump(12)
  CTR
}

## The same expression as the discarded statement of the sibling fixture, but in TAIL position: it
## must be delivered, not dropped.
deliver_tail := fn() -> u64 {
  q : u64 = 7
  q + 1
}

main := fn() -> u64 {
  mut bad : u64 = 0
  if bad == 0 and discard_effect() != 42 { bad = 110 }
  if bad == 0 and CTR != 42 { bad = 111 }
  if bad == 0 and deliver_tail() != 8 { bad = 112 }
  if bad != 0 { return bad }
  42
}
