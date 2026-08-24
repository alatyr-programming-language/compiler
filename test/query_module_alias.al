## QUERY: a renamed module alias must resolve inside compiles/resolves exactly
## as an ordinary alias-qualified call. `comptime if` deliberately reaches the
## lower query mirror after the ordinary sema pass skips comptime branches.
m := std::math

pick_compile := fn() -> u64 {
  comptime if compiles(m::floor(7.0)) { return 20 } else { return 1 }
}
pick_resolve := fn() -> u64 {
  comptime if resolves(m::floor(7.0)) { return 22 } else { return 2 }
}

main := fn() -> u64 { return pick_compile() + pick_resolve() }
