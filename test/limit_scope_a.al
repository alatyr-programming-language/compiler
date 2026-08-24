## sema/§ limits (I9 locality of the TU contract): this file declares `@limits(no_comptime)` and itself
## uses NO comptime — so it is legal. Paired with limit_scope_b.al (which DOES use comptime but declares
## no limit) in a multi-file check: per-file scoping means A's limit must NOT restrict B. (Helper
## limit_scope_multi in e2e.sh runs `check A B` and expects ACCEPT.)
@limits(no_comptime)
aa := fn() -> u64 { return 1 }
