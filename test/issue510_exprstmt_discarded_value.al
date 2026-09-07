## Issue #510 / Declarations §5 — a DISCARDED expression statement's value must not become the
## enclosing function's result. The parser splits a fn body into a statement list plus an OPTIONAL
## trailing expression (`Decl.value`): `{ q : u64 = 7  q + 1  42 }` is the list [q := 7,
## ExprStmt(q + 1)] plus the tail `42`, so the LAST statement has `nx == 0` while the fn's value is
## the tail. `emit_wat_body` passed `tail_value` unconditionally, and on that flag `emit_wat_stmts`
## turns a trailing expression statement into `(return …)` — so the WAT read
## `(return (i64.add …)) (i64.const 42)` and the tail was dead code.
##
## Measured on the parent (`origin/main` 71ea8df), each shape as its own `main`, four backends,
## `alatyr wat` + `wat2wasm` + `wasmtime -C cache=n` for the wasm column:
##
##   shape                                   x86_64  aarch64  riscv64  wasm
##   discarded stmt then tail value              42       42       42     8   <- the issue
##   discarded stmt then explicit `return`       41       41       41    41   (already agreed)
##   nested `return`, discarded stmt, tail       40       40       40     8
##   trailing statement `match`, then tail       43       43       43     5
##
## The three native backends need no such flag: they emit the statements, letting the statement's
## value land in the result register, and then emit the tail expression OVER it (`emit_a64_fn` /
## `emit_rv_fn`: `if (not void) and has_tail { emit …(d.value) }`). Only WASM has to say `drop`, and
## it already knew how — `exprstmt_needs_drop` and the `(drop)` arm were there; the tail-value arm
## was simply preferred over them. The fix gates `tail_value` on `ex_is_no_tail(tail)`, which is the
## same fact the other three read.
##
## Registered with `run` (not `run_x86`), so the a64/rv64/wasm sweeps execute it, PLUS an explicit
## `run_wat` row: the sweeps accept a clean trap, and this fixture's failure is a clean wrong VALUE.
##
## Each shape is probed on its own with a distinct code from 100 so a dropped, swapped or duplicated
## shape names itself instead of aliasing into a shared answer. Every code is below 126 (WASI
## `proc_exit` rejects more) and distinct from 42.
##
## What is deliberately NOT here: a fn body that is a single tail `match` with no trailing
## expression (that shape has no discarded statement and is the arm-yielding path the flag exists
## for), and the effect/tail-delivery controls, which are
## `test/issue510_exprstmt_effect_and_tail.al`.

Pick := enum { A, B }

## THE issue reproducer: the discarded statement is the last statement, and the fn's value is the
## trailing expression after it.
tail_after_discard := fn() -> u64 {
  q : u64 = 7
  q + 1
  42
}

## The same shape closed by an EXPLICIT `return` instead of a trailing expression. A top-level
## `return` already cleared the flag, so this spelling agreed on the parent; it is here because the
## two spellings of "the statement's value is discarded" must not diverge.
return_after_discard := fn() -> u64 {
  q : u64 = 7
  q + 1
  return 41
}

## The `return` is NESTED, so the body-level "has an explicit return" scan does not see it and the
## flag was live again: on the parent this answered 8 on wasm for `c == 0`, and 39 for `c == 1`
## because that path never reaches the discarded statement. Both directions are probed.
nested_return_then_tail := fn(c : u64) -> u64 {
  if c == 1 { return 39 }
  q : u64 = 7
  q + 1
  40
}

## The other statement shape the same flag reaches: a trailing statement `match`. Its arms are bare
## expressions whose values are discarded, so on the parent each arm `return`ed its own value (5 or
## 6) and the tail `43` was dead. Both arms are probed, because a value-yielding match is per-arm.
match_stmt_then_tail := fn(p : Pick) -> u64 {
  match p {
    A => { 5 }
    B => { 6 }
  }
  43
}

main := fn() -> u64 {
  mut bad : u64 = 0
  if bad == 0 and tail_after_discard() != 42 { bad = 100 }
  if bad == 0 and return_after_discard() != 41 { bad = 101 }
  if bad == 0 and nested_return_then_tail(0) != 40 { bad = 102 }
  if bad == 0 and nested_return_then_tail(1) != 39 { bad = 103 }
  if bad == 0 and match_stmt_then_tail(Pick.A) != 43 { bad = 104 }
  if bad == 0 and match_stmt_then_tail(Pick.B) != 43 { bad = 105 }
  if bad != 0 { return bad }
  42
}
