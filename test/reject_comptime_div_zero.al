## e2e — CT-12: a comptime DIVISION BY ZERO is a located diagnostic, not a deferred SIGFPE. This used
## to build green and die with exit 136 on the first run-time path that reached `K`.
## Located at the division (line 4).
K : u64 = 10 / 0

main := fn() -> i64 {
  return i64(K)
}
