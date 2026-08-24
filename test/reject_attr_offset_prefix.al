## e2e (reject) — `@offset(N)` is the FIELD lever of Types §8 ("give a FIELD an explicit offset"): a
## byte position INSIDE an aggregate. A DECLARATION — a binding or a type — has no offset to give, and
## Types §8 is explicit that the levers are not universal ("each targets a specific representational
## degree of freedom, applying only where that freedom exists").
##
## This spelling used to be CONSUMED AND THROWN AWAY without a word: the struct below laid out exactly
## like the un-attributed one, so a user who wrote a register map got a silently different layout. It
## is now a located reject naming the attribute, the target kind and the legal spelling.
@offset(8)
S := struct { a : u8, b : u8 }
main := fn() -> u64 {
  s := S(a = 1, b = 2)
  return u64(s.a) + u64(s.b)
}
