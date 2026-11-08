## e2e — issue #1464, the controls for the DECLARED-type route: a function value whose type is declared
## (a parameter, a struct field) keeps every use Modules §2 and Functions §1.5 give it — a UFCS call
## through a parameter (`h.apply()` ≡ `apply(h)`), a direct call of the parameter, and a function-typed
## field bound and then called. 42 + 42 + 42 - 84 on the parent (`origin/main` `f7011080`) and after,
## on x86_64. aarch64/riscv64 trap (133) and wasm traps (134) on every indirect call (#1196).
f := fn() -> u64 { return 42 }
S := struct { h : fn() -> u64 }
apply := fn(h : fn() -> u64) -> u64 { h() }
via := fn(h : fn() -> u64) -> u64 { h.apply() }
call := fn(h : fn() -> u64) -> u64 { h() }
main := fn() -> u64 {
  s := S(h = f)
  g := s.h
  via(f) + call(f) + g() - 84
}
## expect: run 42
