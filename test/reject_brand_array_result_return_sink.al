## e2e — Issue #687 / Types §4.2-§4.3 + §5.4:395-400, the EARLY-`return` half of the declared
## fixed-array result sink. `mk := fn() -> [A; 2] { return [B(1), B(2)] }` is the same crossing as
## `test/reject_brand_array_result_sink.al` reaching the checker through a different walker, and it
## is its own fixture because it is its own CODE PATH: a trailing expression is judged at
## `check_fn`'s declared-result site, while an early `return` is judged by `ret_sink_err`, the only
## walker that carries the enclosing fn's return-type span into a nested block.
##
## Both walkers read the SAME `Decl.ret_ts`/`ret_tl` pair, and that pair is what was truncated — the
## parser records a `[…]` result type as its `[` head token, so `ret_tl` is 1 and the element walk
## had one byte to find an element type in. So both sinks were open, both are closed by one
## recovery, and without this fixture the `return` half would be an unexercised branch of it: a
## later unit could delete the recovery from `sema_brand_ret_err` and every other row here would
## still pass.
##
## The LEGAL control sits one line above the crossing, and the `check` row pins the refusal's LINE,
## so a refusal that fired on the control would fail that row rather than pass it.
##
## Four-backend witness: the rule is decided in `check` and is target-independent, so the per-file
## manifest carries an x86_64, aarch64, riscv64 and wasm row and each must be a refusal.
##
## Failure-first: on the parent compiler (`main` a65e873) this program checked at rc 0, built at
## rc 0 and ran to its value, with the sibling-branded result compiled into it and the census
## channel reporting `sinks=0` for it.
A := brand(u64)
B := brand(u64)

ok := fn() -> [A; 2] { return [A(4), A(5)] }
mk := fn() -> [A; 2] { return [B(1), B(2)] }

main := fn() -> u64 { return 0 }
