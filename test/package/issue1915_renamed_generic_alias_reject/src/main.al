main := fn() -> u64 { geo::child::run() + geo::pf() - 100 }
## Compiled alone (the corpus walk), this file names a module `geo` it does not have.
## expect: reject
