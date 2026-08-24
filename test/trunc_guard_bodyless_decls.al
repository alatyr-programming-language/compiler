## OVER-REJECT GUARD, second half: the declaration forms that legitimately have NO BODY. The parser now
## requires an ordinary function's signature to be followed by a braced body — the truncation
## `f := fn() -> u64` with nothing after it used to be diagnosed only vaguely by the checker, and its
## mid-file twin swallowed `main` outright — so every form that is CORRECTLY bodyless has to keep
## parsing. All three return before the new requirement is reached, and this fixture is what proves it:
##
##   * `@extern("sym") fn(...) -> R` — an external import (Modules §7.2), paired with an `@export` so
##     the program links against itself;
##   * `@abi(syscall) fn(...) -> R` — a raw-syscall trampoline declaration (Stdlib §7 / ABI);
##   * `fn(T : type) -> type { ... }` — a type function, whose braces belong to a type body rather than
##     to a statement list, and which returns from a different arm of the same declaration parser.
##
## Measured identical on the pre-fix and post-fix compilers: build rc 0, exit 42.
Box := fn(T : type) -> type { struct { v : T } }

sys_write := @abi(syscall) fn(num : usize, fd : usize, buf : usize, len : usize) -> isize

@export("trunc_guard_shared") producer := fn() -> u64 {
  return 40
}

consumer := @extern("trunc_guard_shared") fn() -> u64

main := fn() -> u64 {
  b := Box(u64)(v = 1)
  n := sys_write(1, 1, 0, 0)
  mut acc := consumer() + b.v
  if n == 0 { acc = acc + 1 }
  return acc
}
