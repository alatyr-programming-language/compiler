cfg : u64 = 3
pub get := fn() -> u64 { cfg.x }
## Compiled alone (the corpus walk), this module is refused for the same field read.
## expect: reject "a scalar has no field to name"
