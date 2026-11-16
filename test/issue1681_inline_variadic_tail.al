## e2e — #1681: an `@inline` callee that is ALSO comptime-variadic answers the pack, not 2. Both
## markers expand the callee at the call site with no `call` (Codegen §3.5 / CG-10 for `@inline`,
## Functions §7.1 for the comptime pack), and Control Flow §3 with Functions §3.3/§3.4 makes the body's
## FINAL EXPRESSION fill the `-> u64` output. The call-site dispatch took `@inline` FIRST, and
## `emit_inline_call` binds every parameter as an ordinary value — it never set `cx.pack_args`, so the
## body's `comptime for a in args` unrolled ZERO times and only the tail survived. MEASURED at 1b3b22e0
## (native x86_64, Stage1 built by the committed seed 0.3.2): **2** on default, `x86-legacy` and
## `x86-ir`, where 20 + 20 + 2 = 42 is due; the same callee WITHOUT `@inline` answers 42. The fix hands
## a comptime-variadic callee to `emit_variadic_body`, the one expander that threads the pack.
## spec: Functions §7.1, §3.3/§3.4; Codegen §3.5 (CG-10)
## expect(x86_64): run 42
@inline sum := fn(args : ...) -> u64 {
  mut t : u64 = 0
  comptime for a in args {
    t = t + a
  }
  t + 2
}

main := fn() -> u64 { sum(20, 20) }
