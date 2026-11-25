## No binding of `f` here: the nearest scope that binds it is `geo::child`, through its alias.
pub run := fn() -> u64 { f(40) }
## Compiled alone (the corpus walk), nothing binds the name `f` this file calls.
## expect: reject
