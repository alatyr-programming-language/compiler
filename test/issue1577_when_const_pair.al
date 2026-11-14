## e2e — #1577: a module const declared as a pair of `when` alternatives is read by a function the IR
## builds. A declaration whose guard folds false is absent (Comptime §7.1, §9.2), so each name below has
## exactly one declaration on every target, and the pick the IR makes must skip the absent one.
##
## Each target takes the other row of both pairs, so the sum is 42 everywhere only when both reads pick
## the alternative of the same target: 40 + 2 on x86_64, 41 + 1 elsewhere (wasm has no `Arch` variant,
## FND-6, so it takes the `!=` rows). A pick that ignored the guards would mix the rows (43 or 41).
##
## Parent (200d3376): `alatyr ir` refused both readers, `k` and `j` (NotYet at the name read: two
## declarations of the name, `ib_global_decl` refused the tie), so they fell back to the legacy emitter.
K : u64 = 40 when target.arch == Arch.x86_64
K : u64 = 41 when target.arch != Arch.x86_64
J : u64 = 2 when target.arch == Arch.x86_64
J : u64 = 1 when target.arch != Arch.x86_64

k := fn() -> u64 { K }
j := fn() -> u64 { J }

main := fn() -> u64 {
  k() + j()
}
## expect: run 42
