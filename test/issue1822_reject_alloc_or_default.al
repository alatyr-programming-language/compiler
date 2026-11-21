## #1822 / Functions §5.3, §5.5, spec#171: `dk(42)` is one argument short of `dk`, which declares both an
## allocator parameter and a parameter with a default. Read in order, 42 binds `ar` and `k` takes 7;
## read as eliding the allocator, 42 binds `k` and `ar` has no ambient. Which reading the call means is
## not specified yet, so it is refused rather than guessed. The checker used to accept it and run 7.
dk := fn(ar : ptr(mut Arena), k : u64 = 7) -> u64 { k }
main := fn() -> u64 {
  r := dk(42)
  return r
}
## expect: reject "one argument short of a function with an allocator parameter `ar` and a parameter with a default" "at line 7"
