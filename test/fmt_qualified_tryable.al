## e2e/fmt — a PRELUDE tryable construction whose type argument is a QUALIFIED path,
## a qualified Result/SerError constructor. The fmt driver builds its enum-name table from the file's
## OWN enum decls, and no file declares `Result` / `Option` — so `is_enum_name("Result")` was false,
## the generic-enum-ctor rewrite never fired, and the head parsed as an ordinary call. An ordinary
## call ARGUMENT does not consume a qualified VALUE path's `::seg` tail, so the argument loop ran
## past the closing `)` and swallowed EVERY FOLLOWING DECLARATION into the argument list:
##
##     Result(usize, ser, SerError.Ok(0), main, fn() -> u64 { … })
##
## — one decl where four had stood (`serialize_roundtrip` built before a reformat and not after).
## `compile_file_fmt` now seeds the table with the two prelude names.
ser := std::serialize

enc := fn(in out sb : alloc::strbuf::StrBuf) -> Result(usize, ser::SerError) {
  ser::put_u8(sb, 18)?
  ser::put_u16(sb, 4660)?
  Result(usize, ser::SerError).Ok(0)
}

## a decl AFTER the qualified-tryable one: it must still be its own declaration in the render
tail := fn() -> u64 {
  return 40
}

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut sb := alloc::strbuf::strbuf(ptr(ar), 256)
  mut ok : u64 = 0
  match enc(sb) {
    Ok(z) => { ok = 2 }
    Err(e) => { ok = 0 }
  }
  return tail() + ok
}

sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
