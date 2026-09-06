## e2e / issue #393 (residual) — the OTHER side of the new prelude triggers: a file that declares the
## trigger names ITSELF keeps its own meanings.
##
## Widening a textual trigger is only safe if it cannot break a program that already compiled. This
## file declares all three names the allocator-surface trigger now watches — an arena type of its
## own shape, an error enum with its own variants, and a constructor that is a plain arithmetic
## function — so on this branch it injects the shipped prelude where the parent injected nothing, and
## every declaration below must still be the one that resolves. That is why the trigger needs no veto
## flag of its own, unlike the `uint`/`Slice` triggers whose generic operator sets do collide.
##
## The assertions are chosen so the SHIPPED declarations cannot satisfy them: the shipped arena has
## no such single-field literal, the shipped error enum has none of these variant names, and the
## shipped constructor takes a pointer and a capacity and returns an arena, not `n + 1`.
##
## 42 means every check held. Each miss owns its own code from 100 up.
Arena := struct { cap : u64 }

AllocError := enum { Mine, Yours }

arena_over := fn(n : u64) -> u64 { return n + 1 }

pick := fn(e : AllocError) -> u64 {
  match e {
    Mine => { return 7 }
    Yours => { return 9 }
  }
}

main := fn() -> u64 {
  a := Arena(cap = 5)
  if a.cap != 5 { return 100 }
  if pick(AllocError.Mine) != 7 { return 101 }
  if pick(AllocError.Yours) != 9 { return 102 }
  if arena_over(6) != 7 { return 103 }
  return 42
}
