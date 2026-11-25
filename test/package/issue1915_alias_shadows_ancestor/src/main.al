main := fn() -> u64 { geo::child::run() + geo::child::leaf::run() + geo::pf() - 142 }
## Compiled alone (the corpus walk), this file names a module `geo` it does not have.
## expect: reject
