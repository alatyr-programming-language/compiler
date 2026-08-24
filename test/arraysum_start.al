## e2e — REGALLOC arraysum MEGASHAPE: the full `benchmarks/03_arraysum` `_start` body reduced to a
## `main -> u64` that must exit 42, using the mmap/arena_over setup (only WHITELISTED build calls).
## Exercises all four megashape pieces: (1) `v.push(i * 2)` inside a `while` loop (reads the modeled
## cursor `i`); (2) barriers-NOT-first (`sum := 0` is a modeled stmt BEFORE the `with_capacity`/`while`
## build barriers); (3) the `alloc::with(ar) { … }` block barrier (`Stmt::AllocWith`); (4) the trailing
## `fmt::print` barrier (reads the modeled accumulator `sum`). The `for x in v` sum loop is the
## register-allocated hot loop. The exit code must be IDENTICAL default (regalloc) vs `ALATYR_RA=0`
## (text). 0+2+4+6+8+10+12 = 42.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
fmt := std::fmt
vec := alloc::vec

main := fn() -> u64 {
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)
  mut sum : u64 = 0
  alloc::with(ar) {
    mut v := vec::with_capacity(u64, 8)
    mut i : u64 = 0
    unchecked {
      while i < 7 {
        r2 := v.push(i * 2)
        i += 1
      }
    }
    unchecked {
      for x in v {
        sum += x
      }
    }
  }
  fmt::print("sum = {}\n", sum)
  sum
}
