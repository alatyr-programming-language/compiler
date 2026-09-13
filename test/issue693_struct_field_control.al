## e2e — issue #693 CONTROL 1: a field read on a STRUCT value stays accepted and stays correct.
##
## This is the contrast that makes the refusal non-vacuous: the owner here HAS a member table, the
## selected name is in it, and nothing about this row moves. 55 = 11 + 44 read out of the struct.
S := struct { a : u64, b : u64 }
main := fn() -> u64 {
  s := S(a = 11, b = 44)
  s.a + s.b
}
