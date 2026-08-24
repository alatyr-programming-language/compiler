## std::fmt — structural `Display` rendering over `typeinfo` (Stdlib §2.7;
## Comptime §5.3 / D87). `display(T, v, sb)` renders any value into a `StrBuf`
## (the §2.7 sink) **field by field**: an aggregate as `{ name = value, … }`
## (recursing into each field via `comptime for` over `typeinfo(T).fields` + the
## projection `a.(f)`), a scalar leaf as its base-10 text. Monomorphized per
## type, fully erased — zero-cost, no RTTI.
##
## The `display` body is already recursive (it renders a nested struct field by
## descending into it). Two known interim limits, both additive: (1) v1 leaf
## rendering covers **unsigned** integers (any scalar widened to `u64`) — signed
## / `bool` / `char` / `float` leaves need `TypeInfo.Scalar` to carry the numeric
## **kind** (today only `bits`); (2) a **nested aggregate field** needs the
## backend to read an aggregate field through a by-reference parameter's pointer
## (the aggregate-field-through-pointer call-argument path) — so v1 renders flat
## structs of scalars. The sink is the concrete `StrBuf`; the general
## `Writer`-protocol sink (any type with `write([u8])`) is the §2.7 generalization.

sys_write := @abi(syscall) fn(num : usize, fd : usize, buf : ptr(u8), len : usize) -> isize

## A **`Writer`** over a file descriptor (Stdlib §2.7) — the streaming sink, the
## counterpart of the in-memory `StrBuf`. `stdout()` is fd 1.
pub Stdout := struct { fd : usize }
pub stdout := fn() -> Stdout { return Stdout(fd = 1) }

## `Stdout` satisfies the **`Writer`** shape (Stdlib §2.7): write the slice to the
## fd, returning `Ok(count)` for the bytes the syscall accepted (a short write is
## legal; `write_all` loops) or the mapped `IoError` on a failed `write(2)`.
pub write := fn(in out o : Stdout, bs : Slice(u8)) -> Result(usize, io::IoError) {
  r := unchecked sys_write(1, o.fd, bs.ptr, bs.len)
  if r < 0 {
    e := i32(0 - r)
    return io::io_error_result(usize, e)
  }
  Result(usize, io::IoError).Ok(usize(r))
}

## Write the **whole** slice to any **`Writer`** `W` (a type providing
## `write(in out self, [u8]) -> Result(usize, IoError)`, Stdlib §2.7) — looping
## over short writes. Generic over the sink: the `w.write(…)` call dispatches by
## `W`'s type (UFCS, D67), so output composes against `StrBuf`, `Stdout`, or any
## writer. A failed write **propagates** (`?`); a sink that refuses progress
## (a `0` accept) returns `Ok` with the count written so far. On success returns
## `Ok(bs.len)`.
pub write_all := fn(W : type, E : type, in out w : W, bs : Slice(u8)) -> Result(usize, E) {
  base := unchecked bitcast(usize, bs.ptr)
  mut off : usize = 0
  while off < bs.len {
    rest := Slice(u8)(ptr = unchecked bitcast(ptr(u8), base + off), len = bs.len - off)
    res := w.write(rest)
    match res {
      Result::Ok(n) => {
        if n == 0 {
          return Result(usize, E).Ok(off)
        }
        off += n
      }
      Result::Err(e) => {
        return Result(usize, E).Err(e)
      }
    }
  }
  Result(usize, E).Ok(off)
}

## The **renderer** lives in the **alloc tier** (`alloc::fmt`, D91 — it builds an
## in-memory `StrBuf` and never reaches the OS, so it is usable `freestanding`). It
## is **re-exported** here so the historical `std::fmt::display` / `std::fmt::format`
## paths keep resolving; `print`/`println` below call it and add the std-tier write.
pub display := alloc::fmt::display
pub format := alloc::fmt::format

## **Comptime-variadic** formatted print (Functions §7.1 / Stdlib §2.7): a
## comptime **`{}` template** string with the trailing arguments, of any
## displayable (heterogeneous) type, filling the holes — e.g.
## `print("count = {}, ok = {}\n", n, flag)`. The template is split on `{}` at
## comptime and interleaved with the arguments, each rendered via `display`
## (element type inferred per argument, monomorphized; a `str` segment renders
## verbatim). An adaptive integer **literal** hole argument (`print("{}", 7)`)
## Write a built `StrBuf`'s bytes to standard output — the **std-tier** I/O sink
## (Stdlib §7 / D91 tier discipline). The buffer's bytes are read from the alloc
## tier via its non-consuming accessors (`strbuf_base`/`buf_len`); the **syscall
## lives here in `std`**, never in `alloc` (which must not reach the OS tier — the
## former `alloc::strbuf::print_buf` was that inversion). Returns the `write(2)`
## result. A non-consuming scoped-reference read of the buffer.
pub write_buf := fn(s : ptr(alloc::strbuf::StrBuf)) -> isize {
  p := unchecked bitcast(ptr(u8), bitcast(usize, alloc::strbuf::strbuf_base(s)))
  unchecked sys_write(1, 1, p, alloc::strbuf::buf_len(s))
}

## Write a built `StrBuf`'s bytes to a file at `path` (the std-tier file sink, D91
## tier discipline — the syscall lives in `std`, the bytes are read from the alloc
## tier via the non-consuming `strbuf_base`/`buf_len`). The buffer is viewed as a
## `[u8]` slice and handed to `io::write_file` (open `O_WRONLY|O_CREAT|O_TRUNC`,
## write, close). This is what a self-hosted compiler uses to put its emitted GAS on
## disk for the assembler. Returns the `io::write_file` `Result`.
pub write_buf_file := fn(s : ptr(alloc::strbuf::StrBuf), path : str) -> Result(usize, io::IoError) {
  p := unchecked bitcast(ptr(u8), bitcast(usize, alloc::strbuf::strbuf_base(s)))
  bs : Slice(u8) = Slice(u8)(ptr = p, len = alloc::strbuf::buf_len(s))
  io::write_file(path, bs)
}

## renders as the target's native signed integer (the unconstrained-literal
## default). Void; called in statement position (inlined at the call site).
pub print := fn(fmt : str, args : ...) {
  mut osar := os::arena(4096)
  mut ar := osar.region()
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  comptime for x in args {
    ## Bind `display`'s `Result` to a local first: a call returning an aggregate
    ## passed *directly* as another call's argument is a non-place aggregate arg
    ## (not lowered); the local is a place `trap_oom` consumes.
    rr := alloc::fmt::display(x, sb)
    alloc::fmt::trap_oom(rr)
  }
  d := sb.write_buf()
  g := sb.strbuf_free()
  fa := os::free(osar)
}

## Render `v` to standard output followed by a newline (a `StrBuf` built then
## written once). Returns the `print_buf` syscall result.
pub println := fn(T : type, v : T) -> isize {
  mut osar := os::arena(4096)
  mut ar := osar.region()
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  dr := alloc::fmt::display(T, v, sb)
  alloc::fmt::trap_oom(dr)
  nr := alloc::strbuf::push_byte(sb, 10)
  alloc::fmt::trap_oom(nr)
  r := sb.write_buf()
  f := sb.strbuf_free()
  fa := os::free(osar)
  r
}

## Render `v` to standard output with NO trailing newline (println minus the newline). The
## per-argument renderer the `{}`-template `print` desugar calls for each hole — the compiler
## expands `print("a {} b", x)` to `io::print("a ") ; print_one(x) ; io::print(" b")`, so each
## piece writes in order. Returns the `write_buf` syscall result.
pub print_one := fn(T : type, v : T) -> isize {
  mut osar := os::arena(4096)
  mut ar := osar.region()
  mut sb := alloc::strbuf::strbuf(ptr(ar), 64)
  dr := alloc::fmt::display(T, v, sb)
  alloc::fmt::trap_oom(dr)
  r := sb.write_buf()
  f := sb.strbuf_free()
  fa := os::free(osar)
  r
}

## Render an UNCONSTRAINED INTEGER LITERAL hole to stdout (no newline) — the target's native signed
## `i64` (Functions §7.1: the unconstrained-literal default). NON-generic, so the `{}`-template
## desugar can emit `call print_one_int` for a bare-literal hole (`print("{}", 5)`) without a
## type-argument span. Returns the write byte count.
pub print_one_int := fn(v : i64) -> isize {
  print_one(i64, v)
}

## Render a FLOAT hole to stdout (no newline) — base-10 with a bounded fractional part (Stdlib
## appendix §2; the interim float formatter). NON-generic (float ABI: `v` arrives in %xmm0), so the
## `{}`-template desugar emits `call print_one_float` for a float hole without a type-argument span.
pub print_one_float := fn(v : f64) -> isize {
  print_one(f64, v)
}
