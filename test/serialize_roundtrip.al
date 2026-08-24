## e2e — std::serialize little-endian binary encode/decode round-trip. Encode a mix
## of primitive values into a StrBuf over an arena, then decode them back IN ORDER
## through a bounds-checked Reader and verify each equals what was put in. The u64
## 0x0102030405060708 pins little-endian byte order, and f64 is checked bit-identical
## (bitcast to u64) so an exact round-trip is proven. Returns 42 iff every field
## round-trips; a distinct early return per field so a regression is diagnosable.
ser := std::serialize
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

enc := fn(in out sb : alloc::strbuf::StrBuf) -> Result(usize, ser::SerError) {
  ser::put_u8(sb, 18)?
  ser::put_u16(sb, 0x3456)?
  ser::put_u32(sb, 0x789ABCDE)?
  ser::put_u64(sb, 0x0102030405060708)?
  ser::put_i32(sb, 0 - 12345)?
  ser::put_bool(sb, true)?
  ser::put_f64(sb, 3.14159265358979)?
  ser::put_str(sb, "hi")?
  ser::put_bytes(sb, bytes("XY"))?
  ser::put_i64(sb, 0 - 9000000000)?
  Result(usize, ser::SerError).Ok(0)
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)

  mut sb := alloc::strbuf::strbuf(ptr(ar), 256)
  match enc(sb) { Ok(z) => { } Err(e) => { return 90 } }

  base := alloc::strbuf::strbuf_base(ptr(sb))
  ln := alloc::strbuf::buf_len(ptr(sb))
  data := Slice(u8)(ptr = unchecked bitcast(ptr(u8), bitcast(usize, base)), len = ln)
  mut rd := ser::reader(data)

  match ser::get_u8(rd)  { Ok(v) => { if v != 18 { return 1 } }               Err(e) => { return 2 } }
  match ser::get_u16(rd) { Ok(v) => { if v != 0x3456 { return 3 } }           Err(e) => { return 4 } }
  match ser::get_u32(rd) { Ok(v) => { if v != 0x789ABCDE { return 5 } }       Err(e) => { return 6 } }
  match ser::get_u64(rd) { Ok(v) => { if v != 0x0102030405060708 { return 7 } } Err(e) => { return 8 } }
  match ser::get_i32(rd) { Ok(v) => { if i64(v) != (0 - 12345) { return 9 } } Err(e) => { return 10 } }
  match ser::get_bool(rd) { Ok(v) => { if not v { return 11 } }               Err(e) => { return 12 } }
  match ser::get_f64(rd) { Ok(v) => { if bitcast(u64, v) != bitcast(u64, 3.14159265358979) { return 13 } } Err(e) => { return 14 } }
  sv := ser::get_str(rd)
  if sv != "hi" { return 15 }
  bl := ser::get_bytes(rd)
  if bl.len != 2 { return 16 }
  if bl[0] != 88 { return 17 }   ## 'X'
  if bl[1] != 89 { return 18 }   ## 'Y'
  match ser::get_i64(rd) { Ok(v) => { if v != (0 - 9000000000) { return 19 } } Err(e) => { return 20 } }

  ## A short read past the end must be reported, not silently return garbage.
  match ser::get_u8(rd) { Ok(v) => { return 21 } Err(e) => { } }

  return 42
}
