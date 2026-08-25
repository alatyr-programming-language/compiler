## fmt fixture — the COMPTIME `when` GUARD (Comptime §7.1/§9, CT-4/CT-5) in all three positions it is
## written. The guard gates a declaration's EXISTENCE and is consumed by the parser, recorded nowhere
## on the `Decl`, so fmt dropped it — and two complementary guarded declarations of one name then came
## back as an unguarded DUPLICATE (`check: duplicate name`) instead of one live decl.
## Three shapes, all recovered verbatim:
##   • a fn guard after the return type — the x86_64 architecture guard on `answer`
##   • a fn guard whose PREDICATE ITSELF CONTAINS BRACES — `when match typeinfo(T) { … } { body }`.
##     Stopping at the first `{` truncated the guard, the render no longer parsed, and the SECOND fmt
##     pass segfaulted. The body brace is the last `{…}` group of the decl, not the first.
##   • a value-binding tail — `bonus := 100 when target.arch == Arch.riscv64`
## Returns 42.
S := struct { a : u64, b : u64 }

pick := fn(T : type, x : u64) -> u64 when match typeinfo(T) { Struct(_) => true; _ => false } { x }

answer := fn() -> u64 when target.arch == Arch.x86_64 { return 22 }
answer := fn() -> u64 when target.arch == Arch.aarch64 { return absent_on_x86() }

bonus := 100 when target.arch == Arch.riscv64
bonus := 20 when target.arch == Arch.x86_64

main := fn() -> u64 {
  answer() + bonus + pick(S, 0)
}
