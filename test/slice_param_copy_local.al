## e2e — REGRESSION LOCK for a front-end (check/sema) CRASH: binding a `Slice(T)` PARAM to a local
## (`t := s`) made the SELF-HOSTED compiler SIGSEGV at COMPILE time — `alatyr check` on this program
## died with signal 11, a hardware fault, not a diagnostic. The frozen bootstrap seed compiled the
## same program fine, so this had regressed INTO the self-hosted front-end.
##
## Root cause (`src/sema.al`, `Stmt::Assign`): a fresh `x := <value>` binding seeded the local's
## recorded type-NAME span from `tv.ns`/`tv.nl`, the `Ty` returned by `check_expr` through the PACKED
## `Result(Ty, CheckErr)` carrier. That carrier preserves only the TAG — the two span words are stack
## GARBAGE (the tag-5 pointer recovery beside it already documented the same truncation). A `Slice(T)`
## annotation resolves to the NOMINAL library struct `Slice` (`lib/base/slice.al`), i.e. tag 3, so the
## D86 leak probe (`check_leaks` → `local_is_owning` → `type_is_owning`) fired on the binding and did
## `streq(src + <garbage>, …)` — with the garbage typically a whole ABSOLUTE address, that read is far
## outside the source buffer. Plain struct params never tripped it: the same garbage was there, it just
## happened not to land on a decl name of matching length. The fix records UNKNOWN (0/0) and lets only
## RELIABLE storage (callee return type / annotation / aggregate-literal recovery) supply the name.
##
## Values: 4 + 7 = 11. The `.len` of the copied view must survive the copy — a lost length reads 0.
blen := fn(s : Slice(u8)) -> u64 {
  t := s                              ## the binding that used to CRASH the compiler
  return u64(t.len)
}

main := fn() -> u64 {
  bs : [4]u8 = [1, 2, 3, 4]
  cs : [7]u8 = [1, 2, 3, 4, 5, 6, 7]
  a := blen(bs[0..4])
  b := blen(cs[0..7])
  if a != 4 { return 1 }
  if b != 7 { return 2 }
  return a + b
}
