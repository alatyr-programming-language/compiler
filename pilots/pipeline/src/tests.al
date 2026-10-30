## The hashing module's tests: `alatyr test` in this directory. The FNV-1a values are the published
## 64-bit FNV-1a test vectors; the xorshift values come from the reference recurrence.

@test("fnv1a with seed 0 matches the published vectors") fn() {
  if hash::fnv1a(0, bytes("")) != 0xcbf29ce484222325 { panic("empty") }
  if hash::fnv1a(0, bytes("a")) != 0xaf63dc4c8601ec8c { panic("a") }
  if hash::fnv1a(0, bytes("foobar")) != 0x85944171f73967e8 { panic("foobar") }
}

@test("the seed separates equal chunks") fn() {
  if hash::fnv1a(1, bytes("a")) != 0xaf63dd4c8601ee3f { panic("seed 1") }
}

@test("xorshift follows the reference recurrence") fn() {
  s1 := hash::xorshift(1)
  if s1 != 0x40822041 { panic("step 1") }
  if hash::xorshift(s1) != 0x100041060c011441 { panic("step 2") }
}

@test("fold does not depend on order") fn() {
  x := hash::fold(hash::fold(0, 0xffffffffffffffff), 2)
  y := hash::fold(hash::fold(0, 2), 0xffffffffffffffff)
  if x != y or x != 1 { panic("fold") }
}
