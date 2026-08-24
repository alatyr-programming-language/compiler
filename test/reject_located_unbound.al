## ROADMAP §1 item 6 / §5: a poison-only rejection (one that never propagates through the check
## `Err` channel — here an unbound name in a `return` value, caught by `mark_failed`) must still
## carry a SOURCE LOCATION into the diagnostic ("at line N"), not print "location not tracked".
## The reference to `nonexistent_var` on line 8 is unbound.
main := fn() -> u64 {
  mut acc : u64 = 0
  acc = acc + 1
  return nonexistent_var
}
