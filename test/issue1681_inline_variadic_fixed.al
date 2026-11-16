## e2e — #1681, the fixed-args half: an `@inline` comptime-variadic with a LEADING FIXED parameter binds
## the fixed arg AND the pack. `emit_variadic_body` pops the fixed args into scratch, aliases each fixed
## param, then points `cx.pack_args` at the first trailing arg; taking the `@inline` expander first lost
## the pack (and mis-sized the fixed args), so this is the shape that proves both halves survive the
## routing change: 10 + 10 + 20 + 2 = 42. MEASURED at 1b3b22e0 (native x86_64) with base 100: **102**, base + tail with the
## pack lost; with base 10 the parent answers **12** on default, x86-legacy and x86-ir (measured).
## (42, not 132: 132 is x86_64's trap status, so fixture_expect reads `run 132` as a trap.)
## spec: Functions §7.1, §3.3/§3.4; Codegen §3.5 (CG-10)
## expect(x86_64): run 42
@inline accum := fn(base : u64, args : ...) -> u64 {
  mut t : u64 = base
  comptime for a in args {
    t = t + a
  }
  t + 2
}

main := fn() -> u64 { accum(10, 10, 20) }
