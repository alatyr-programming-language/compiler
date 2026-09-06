## Issue #426 — a diagnostic longer than the decoder's old fixed buffer must still be PRINTED.
##
## The two `src/driver.al` decoders assembled their message into a `strbuf(…, 256)`, and
## `rt::sb_byte` panics on overflow. Measured on the parent compiler: the assembled text printed in
## full up to 249 bytes and, at 250, the whole message was replaced by the runtime abort
##
##     rt: StrBuf overflow
##
## so the user of a program with an error got a crashed compiler instead of the located error. The
## variable part is the module name, which is the user's FILE NAME: the longest message in the set
## is 183 bytes, plus the `alatyr: check: ` prefix and the ` at line N in <module>` tail, leaving
## roughly 34 characters of head-room. This module's own stem is 51 characters, so the message it
## provokes is 266 bytes — 17 past the old wall and a hard abort on the parent.
##
## Nothing about the PROGRAM below is new: it is the ordinary `global_init_call` reject (a const
## module-level global initialized by a runtime call returning an aggregate). Only the length of
## the file name is the test, which is why the assertion greps the message's TAIL together with its
## location and this module's name — a bare non-zero exit is also what the abort produced.
Pair := struct { a : u64, b : u64 }

make_pair := fn() -> Pair {
  Pair(a = 1, b = 2)
}

BAD_GLOBAL := make_pair()

main := fn() -> u64 {
  BAD_GLOBAL.a
}
