## e2e — #1633: a whole-value assignment to an `out` / `in out` struct or enum parameter reaches the
## caller's place (Functions §2.1: such a parameter denotes the caller's place; §2.3: it is read and
## written in place; §4.1: it is passed by reference to that place). The IR builds the three callees;
## `main` stays on each backend's legacy emitter (its generic call `id(u64, 0)` is refused by the IR), so
## this pins a legacy caller handing its place to an IR-built callee. `swap` reads the old `p` in the
## value it stores: the value is built whole before the store, so `s` becomes P(20, 1), not P(20, 20).
## 19 (swap) + 8 (fill) + 15 (sete) = 42.
## spec: Functions §2.1, §2.3, §4.1
## expect: run 42
P := struct { a : u64, b : u64 }
E := enum { A(u64), B(u64, u64) }

id := fn(T : type, x : T) -> T { x }

swap := fn(in out p : P) { p = P(a = p.b, b = p.a) }
fill := fn(out p : P) { p = P(a = 5, b = 3) }
sete := fn(in out e : E) { e = E.B(7, 8) }

main := fn() -> u64 {
  mut s := P(a = 1, b = 20)
  swap(s)
  mut f := P(a = 0, b = 0)
  fill(f)
  mut e := E.A(1)
  sete(e)
  mut ev : u64 = 0
  match e { A(x) => { ev = 100 }; B(x, y) => { ev = x + y } }
  s.a - s.b + f.a + f.b + ev + id(u64, 0)
}
