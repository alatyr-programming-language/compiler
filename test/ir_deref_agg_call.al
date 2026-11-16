## e2e — #1723 and #1345: a struct read WHOLE through `deref(<call>)` and passed straight on by value.
## `deref(p)` in value context loads the pointee (Memory §4.3). The shared IR copies a WORD-tier struct
## out of the address the call returns into a fresh object, and passes that object on as any struct
## argument (`sum(deref(get(p)))`, `v : S = deref(get(p))`). x86_64's legacy emitter passed the first
## word of the pointee in place of the struct's address, so `sum` dereferenced 5 and the parent died with
## SIGSEGV (139). Here every function is IR-built.
## No `Option(ptr(T))` appears in this file on purpose. In an emitting compile, the first declaration
## sema's record walk refuses leaves every later one without records (#1028), and so on the legacy
## emitter. An `Option(ptr(u64))` before this shape is one such refusal (measured).
## Each check answers its own code when it fails; 42 when all held.
S := struct { a : u64, b : u64 }

get := fn(p : ptr(mut S)) -> ptr(mut S) { p }
sum := fn(s : S) -> u64 { s.a + s.b }
through_call := fn(p : ptr(mut S)) -> u64 { sum(deref(get(p))) }
bound := fn(p : ptr(mut S)) -> u64 {
  v : S = deref(get(p))
  p.a = 70
  v.a * 10 + v.b
}

main := fn() -> u64 {
  mut t := S(a = 5, b = 6)
  if through_call(ptr(mut t)) != 11 { return 1 }
  if bound(ptr(mut t)) != 56 or t.a != 70 { return 2 }
  if sum(deref(get(ptr(mut t)))) != 76 { return 3 }
  return 42
}
## expect: run 42
