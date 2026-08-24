## P3-RA-AGG bounded next seam: after the admitted u64(x) byte widening, a target-native
## usize(u64(x)) alias cast is another word-identity. The direct index, ordinary u8 call,
## binary-inside-conversion, and checked narrow-arithmetic neighbors are deliberately outside
## this seam. (A bare usize(x) is not used: the current text path does not preserve its u8
## zero-extension, so admitting it would not have a correct ALATYR_RA=0 control.)

Slice := fn(T : type) -> type { return struct { ptr : ptr(T), len : usize } }

sum_usize := fn(s : Slice(u8)) -> u64 {
  mut acc : usize = 0
  for x in s { acc = acc + usize(u64(x)) }
  u64(acc)
}

## Direct indexing remains text-lowered.
read_index := fn(s : Slice(u8), i : usize) -> u64 { u64(s[i]) }

## A call whose callee has a narrow u8 parameter remains text-lowered.
take_byte := fn(x : u8) -> u64 { u64(x) }
sum_call := fn(s : Slice(u8)) -> u64 {
  mut acc : u64 = 0
  for x in s { acc = acc + take_byte(x) }
  acc
}

## A binary nested inside a conversion remains text-lowered, preserving its narrow checked op.
sum_binary := fn(s : Slice(u8)) -> u64 {
  mut acc : u64 = 0
  for x in s { acc = acc + u64(x + 1) }
  acc
}

## Checked narrow arithmetic remains text-lowered and fail-loud (the safe call still returns 5).
narrow_checked := fn(a : u8, b : u8) -> u64 { u64(a + b) }

main := fn() -> u64 {
  mut b : [u8; 4] = [2, 3, 5, 7]
  s := Slice(u8)(ptr = ptr(b[0]), len = 4)
  if read_index(s, 2) != 5 { return 1 }
  if sum_usize(s) != 17 { return 2 }
  if sum_call(s) != 17 { return 3 }
  if sum_binary(s) != 21 { return 4 }
  if narrow_checked(2, 3) != 5 { return 5 }
  17
}
