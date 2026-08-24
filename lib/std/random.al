## std::random — a small, self-contained pseudo-random generator (splitmix64).
##
## Deterministic and SEEDABLE: the same seed always yields the same stream (reproducible tests, sampling,
## procedural generation). No OS entropy is consumed — seed it yourself (a fixed seed for reproducibility,
## or e.g. a time/`getrandom` value for unpredictability). splitmix64 has excellent distribution + speed
## and NO bad seeds (every u64 seed is fine); it is the canonical seeder for the xoshiro/xoroshiro family.
## All state transitions are WRAPPING u64 arithmetic (hence `unchecked`).

Rng := struct { state : u64 }

## A generator seeded with `seed` (any u64).
pub seeded := fn(seed : u64) -> Rng { Rng(state = seed) }

## The next raw 64-bit value, advancing the state (splitmix64: `state += GOLDEN`, then an avalanche mix).
pub next_u64 := fn(in out r : Rng) -> u64 {
  unchecked {
    r.state = r.state + 11400714819323198485
    mut z := r.state
    z = (z ^ z.shr(30)) * 13787848793156543929
    z = (z ^ z.shr(27)) * 10723151780598845931
    z ^ z.shr(31)
  }
}

## A value in the half-open range `[lo, hi)` (caller ensures `hi > lo`). Modulo reduction — negligibly
## biased for ordinary ranges; use `next_u64` directly if you need the full unbiased 64-bit space.
pub next_range := fn(in out r : Rng, lo : u64, hi : u64) -> u64 {
  span := hi - lo
  v := next_u64(r)
  unchecked { lo + v % span }
}

## A fair coin flip.
pub next_bool := fn(in out r : Rng) -> bool { next_u64(r) & 1 == 1 }
