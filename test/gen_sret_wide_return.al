## e2e — a GENERIC fn whose declared return type IS its type parameter (`mk(T : type) -> T`),
## instantiated at a struct TOO WIDE for the register-return budget (>= 8 words), must take the SAME
## SRET path (hidden %rdi result pointer) a CONCRETE wide return takes. The sret decision has to be
## made on the MONOMORPHIZED return type: the declared span is the bare `T`, which resolves to no
## struct at all, so the decision used to fall through on BOTH sides — the caller sized the binding as
## a bare scalar and read the value back from %rax:%rdx:… (a >7-word value the callee never put
## there). Every field read 0: a SILENT MISCOMPILE.
##
## Covers, in one program: the 7-word BOUNDARY (still the register-return convention — must stay
## sound), a 10-word SRET return of a struct LITERAL with a real value arg (which shifts to %rsi
## because %rdi carries the result pointer), and a 10-word SRET return of a frame LOCAL (`return v`).
## Returns (1+7) + (4+9) + (2+3) = 26.
S7 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64 }
S10 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64, j : u64 }

mk7 := fn(T : type) -> T { return S7(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7) }
mk10 := fn(T : type, x : u64) -> T { return S10(a = x, b = 0, c = 0, d = 0, e = 0, f = 0, g = 0, h = 0, i = 0, j = 9) }
mk10v := fn(T : type) -> T {
  v := S10(a = 2, b = 0, c = 0, d = 0, e = 0, f = 0, g = 0, h = 0, i = 0, j = 3)
  return v
}

main := fn() -> u64 {
  p := mk7(S7)          ## 7 words — the register-return boundary (words 0..6 = %rax..%r11)
  q := mk10(S10, 4)     ## 10 words — SRET, struct-literal return, one real value arg
  r := mk10v(S10)       ## 10 words — SRET, `return <local>` (the Var form)
  u64(p.a + p.g + q.a + q.j + r.a + r.j)   ## 8 + 13 + 5 = 26
}
