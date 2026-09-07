## issue #514 control — the SAME `checked_add` program as `test/issue514_checked_bare.al` except
## that the result type is written out. On the parent compiler this one already answered 42, because
## the bare `Option` reference tripped the neighbouring ambient trigger in `src/cli.al` and pulled
## the base prelude that the `checked_` trigger should have pulled. It is registered so the fix
## cannot regress the spelling that used to be the only working one; the pair of files is the
## measurement that the difference was one word of unrelated source text.
main := fn() -> u64 {
  a : u64 = 41
  o : Option(u64) = checked_add(a, 1)
  if is_none(o) { return 1 }
  if unwrap(o) != 42 { return 2 }
  42
}
