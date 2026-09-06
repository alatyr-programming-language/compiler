## e2e/fmt — the `bitcast` targets `p_factor` IDENTITY-ERASES, which `alatyr fmt` used to delete from
## the author's own file at exit 0 (issue #397, Tooling §4.3 / §4.3.4).
##
## The parser builds an `Expr::Bitcast` node only for a target the lowerers need something extra for
## (a sub-word scalar, a pointer to one, a pointer to a user type, a bare aggregate name). For a
## word-sized scalar, `str`, `type`, or a pointer over one of those, the cast is the identity on the
## block and the node is DROPPED — so the written target left no trace in the tree at all and fmt
## re-emitted the bare operand wrapped in parentheses. The conversion the author wrote was gone, the
## output was idempotent, and the program still ran: nothing in the corpus arbiter could see it,
## which is why the companion `fmt_test_has_all` needles and not the exit status are the assertion.
##
## The four shapes below are the ones with independent recovery paths: a word-scalar target used as a
## CALL ARGUMENT (the position issue #397 reported), the same target NESTED inside a second erased
## cast (two levels on one node, which must come back outermost-first, and only the outer one carries
## the verification-mode marker), a pointer whose pointee is a word-sized scalar (the whole
## parenthesised target span, not just its head), and a `str` target written with NO marker — that
## last one fails just as loudly if the marker is INVENTED as if the cast is dropped.
##
## Each check returns its own distinct status, so a permutation of the checks cannot be mistaken for
## a pass; 42 is reached only when all four hold.
sink := fn(n : usize) -> u64 { u64(n) }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  arg := sink(unchecked bitcast(usize, neg1))
  if arg != 18446744073709551615 { return 11 }

  wide := unchecked bitcast(u64, bitcast(usize, neg1))
  if wide != 18446744073709551615 { return 12 }

  mut cell : usize = 7
  addr := unchecked bitcast(usize, ptr(mut cell))
  word := unchecked bitcast(ptr(usize), addr)
  if deref(word) != 7 { return 13 }

  text := bitcast(str, "ok")
  if text.len != 2 { return 14 }

  return 42
}
