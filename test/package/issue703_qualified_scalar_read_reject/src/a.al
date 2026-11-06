pub get := fn() -> u64 { z::n.x }
## Compiled alone (the corpus walk), this file names a module `z` it does not have.
## expect: reject
