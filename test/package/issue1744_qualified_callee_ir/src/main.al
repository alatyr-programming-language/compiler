## The root's own `S`, laid out differently from `m`'s. It is only declared: a program that lays out
## both is the legacy x86 defect #1734 (fixed by #1743), which this fixture does not measure.
S := struct { tag : u8, n : u64, k : u64 }
sum := fn() -> u64 { m::add(19, 3) }
fields := fn() -> u64 {
  q := m::mkq(5, 6)
  q.a + q.b
}
theirs := fn() -> u64 { m::get(m::mks(1, 9)) }
main := fn() -> u64 { sum() + fields() + theirs() }
## Compiled alone (the corpus walk), this file names a module `m` it does not have.
## expect: reject
