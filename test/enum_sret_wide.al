## e2e — an ENUM whose payload is too WIDE for the register-return convention (disc + payload > 7
## words) is delivered via SRET (the hidden result-pointer path, like a wide struct), not truncated.
## `W.Some(Big)` is disc + 7 payload words = 8 words > the %rax..%r11 budget; the callee writes the
## whole enum through %rdi and the caller reads it back from the destination. Exercises the EnumLit
## sret write (struct-literal payload), the Var sret return, the unit-variant (None) write, and the
## caller pointer-passing. Returns 42: Some → sum(1..7)=28, plus the None arm's 14.
Big := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64 }
W := enum { Some(Big), None }

mkV := fn() -> W { W.Some(Big(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7)) }
mkN := fn() -> W { W.None }

main := fn() -> u64 {
  v := mkV()
  n := mkN()
  s := match v { W::Some(x) => x.a + x.b + x.c + x.d + x.e + x.f + x.g, W::None => 0 }   ## 28
  t := match n { W::Some(x) => 0, W::None => 14 }                                         ## 14
  s + t                                                                                    ## 42
}
