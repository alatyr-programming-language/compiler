## e2e — IR slice 3d step 2: a one- or two-word struct RESULT is returned in the target's result
## registers (x86_64 %rax/%rdx, aarch64 x0/x1, riscv64 a0/a1) — the convention every legacy emitter uses
## for such a struct — so an IR-built function and a legacy-emitted one return structs to each other in
## both directions (docs/ir-slice-3.md Q4, proved here).
##
## `lg_*` keep a float local — slice 8's construct (an `Option(u64)` local served until slice 4a built
## enums) — so the shared IR refuses them and
## they stay LEGACY-emitted; `mk`, `one`, `id` and `main` are IR-built.
##   * IR callee -> IR caller: `mk(…)` bound to a local and passed on as an argument (`take(mk(…))`);
##     a field read straight off the call (`mk(…).y`) is pinned by the `ig_agg_ret` IR golden instead,
##     because the LEGACY wasm emitter cannot lower it yet and a wasm trap here would be a new
##     cross-backend disagreement;
##   * IR callee -> legacy caller: `lg_use` reads `mk(…)`;
##   * legacy callee -> IR caller: `main` reads `lg_mk(…)`;
##   * a one-word struct (`one`) and a by-reference parameter returned whole (`id`).
## Each check returns its own code on failure; 42 when all hold, on all four backends.
P := struct { x : u64, y : u64 }
W := struct { v : u64 }

mk := fn(a : u64) -> P { return P(x = a, y = a + 1) }
one := fn(a : u64) -> W { W(v = a * 2) }
id := fn(p : P) -> P { return p }
take := fn(p : P) -> u64 { return p.x + p.y }

lg_mk := fn(a : u64) -> P {
  w : f64 = 1.0
  return P(x = a, y = 7)
}

lg_use := fn() -> u64 {
  w : f64 = 1.0
  p := mk(10)
  return p.x + p.y
}

main := fn() -> u64 {
  p := mk(3)
  if p.x != 3 or p.y != 4 { return 1 }
  m5 := mk(5)
  if m5.y != 6 { return 2 }
  if take(mk(1)) != 3 { return 3 }
  if lg_use() != 21 { return 4 }
  q := lg_mk(9)
  if q.x != 9 or q.y != 7 { return 5 }
  w := one(21)
  if w.v != 42 { return 6 }
  r := id(p)
  if r.x != 3 or r.y != 4 { return 7 }
  42
}
