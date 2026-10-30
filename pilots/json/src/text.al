## JSON text: `parse` reads a document into a `value::Value` tree, `render` writes one
## back as compact text. Both allocate only from the arena the caller passes.
##
## The grammar is RFC 8259's: one value, optionally surrounded by whitespace; no
## comments, no trailing commas, no leading `+` or leading zeros in numbers. Strings are
## decoded (escapes resolved, surrogate pairs joined) on the way in and re-escaped on the
## way out.

Value := value::Value
Member := value::Member
String := alloc::string::String

## Why a parse failed.
pub ErrorKind := enum {
  UnexpectedEnd,     ## the text ended inside a value
  UnexpectedByte,    ## a byte that cannot start or continue the current construct
  BadNumber,         ## a malformed number (`01`, `1.`, `-`, `1e`)
  BadEscape,         ## an unknown `\` escape, a short `\u`, or an unpaired surrogate
  ControlInString,   ## a raw byte below 0x20 inside a string
  TrailingData,      ## something other than whitespace after the value
  TooDeep,           ## arrays and objects nested deeper than `MAX_DEPTH`
  OutOfMemory,       ## the arena could not grow a container or string
}

## A parse failure and where it happened: `offset` is the 0-based byte offset of the
## offending byte (or of the end of the text), `line` and `column` are 1-based, the column
## counted in bytes.
pub Error := struct {
  kind : ErrorKind,
  offset : usize,
  line : usize,
  column : usize,
}

## The deepest nesting of arrays and objects `parse` accepts. The parser recurses once per
## level, so the bound keeps hostile input from exhausting the stack.
pub MAX_DEPTH : usize = 128

## The bytes the grammar names.
TAB : u8 = 0x09
LF : u8 = 0x0A
CR : u8 = 0x0D
SPACE : u8 = 0x20
QUOTE : u8 = 0x22         ## "
PLUS : u8 = 0x2B          ## +
COMMA : u8 = 0x2C         ## ,
MINUS : u8 = 0x2D         ## -
DOT : u8 = 0x2E           ## .
SLASH : u8 = 0x2F         ## /
DIGIT0 : u8 = 0x30        ## 0
DIGIT1 : u8 = 0x31        ## 1
DIGIT9 : u8 = 0x39        ## 9
COLON : u8 = 0x3A         ## :
UPPER_E : u8 = 0x45       ## E
LBRACKET : u8 = 0x5B      ## [
BACKSLASH : u8 = 0x5C     ## \
RBRACKET : u8 = 0x5D      ## ]
LOWER_B : u8 = 0x62       ## b
LOWER_E : u8 = 0x65       ## e
LOWER_F : u8 = 0x66       ## f
LOWER_N : u8 = 0x6E       ## n
LOWER_R : u8 = 0x72       ## r
LOWER_T : u8 = 0x74       ## t
LOWER_U : u8 = 0x75       ## u
LBRACE : u8 = 0x7B        ## {
RBRACE : u8 = 0x7D        ## }
BACKSPACE : u8 = 0x08
FORMFEED : u8 = 0x0C

## The parser's cursor over the input bytes.
Parser := struct {
  text : str,
  src : Slice(u8),
  pos : usize,
  depth : usize,
  a : ptr(mut Arena),
}

## Parse `text` as one JSON document. Containers and decoded strings are allocated from
## `a`; the tree stays valid until that arena is freed.
pub parse := fn(a : ptr(mut Arena), text : str) -> Result(Value, Error) {
  mut p := Parser(text = text, src = bytes(text), pos = 0, depth = 0, a = a)
  ## blocked-by: #1160, #1161 — neither `v := parse_value(p)?` nor a bound `match` with a
  ## `return` arm compiles, so the value is used inside the `Ok` arm.
  match parse_value(p) {
    Ok(v) => {
      skip_ws(p)
      if p.pos < p.src.len {
        return Result(Value, Error).Err(fail(p, ErrorKind.TrailingData))
      }
      Result(Value, Error).Ok(v)
    }
    Err(e) => {
      Result(Value, Error).Err(e)
    }
  }
}

## An `Error` of `kind` at the parser's current position.
fail := fn(in p : Parser, kind : ErrorKind) -> Error {
  mut line : usize = 1
  mut column : usize = 1
  mut i : usize = 0
  while i < p.pos {
    if p.src[i] == LF {
      line += 1
      column = 1
    } else {
      column += 1
    }
    i += 1
  }
  Error(kind = kind, offset = p.pos, line = line, column = column)
}

## A failed arena growth, as a parse error at the current position.
room := fn(in p : Parser, r : Result(usize, AllocError)) -> Result(usize, Error) {
  match r {
    Ok(n) => {
      Result(usize, Error).Ok(n)
    }
    Err(_) => {
      Result(usize, Error).Err(fail(p, ErrorKind.OutOfMemory))
    }
  }
}

## The byte under the cursor; the end of the text is an `UnexpectedEnd` there.
need := fn(in p : Parser) -> Result(u8, Error) {
  if p.pos < p.src.len {
    return Result(u8, Error).Ok(p.src[p.pos])
  }
  Result(u8, Error).Err(fail(p, ErrorKind.UnexpectedEnd))
}

## Whether the byte under the cursor is `b` (false at the end of the text).
at_byte := fn(in p : Parser, b : u8) -> bool {
  p.pos < p.src.len and p.src[p.pos] == b
}

skip_ws := fn(in out p : Parser) {
  while p.pos < p.src.len {
    b := p.src[p.pos]
    if b != SPACE and b != TAB and b != LF and b != CR { return }
    p.pos += 1
  }
}

## Consume `word` (the rest of `true`, `false` or `null`) or fail at the first byte that
## differs.
expect_word := fn(in out p : Parser, word : str) -> Result(usize, Error) {
  for w in bytes(word) {
    if need(p)? != w {
      return Result(usize, Error).Err(fail(p, ErrorKind.UnexpectedByte))
    }
    p.pos += 1
  }
  Result(usize, Error).Ok(word.len)
}

parse_value := fn(in out p : Parser) -> Result(Value, Error) {
  skip_ws(p)
  b := need(p)?
  if b == LBRACE { return parse_object(p) }
  if b == LBRACKET { return parse_array(p) }
  if b == QUOTE {
    ## blocked-by: #1160 — `s := parse_string(p)?` is refused (a `str` Ok payload).
    match parse_string(p) {
      Ok(s) => {
        return Result(Value, Error).Ok(Value.Str(s))
      }
      Err(e) => {
        return Result(Value, Error).Err(e)
      }
    }
  }
  if b == LOWER_T {
    expect_word(p, "true")?
    return Result(Value, Error).Ok(Value.Bool(true))
  }
  if b == LOWER_F {
    expect_word(p, "false")?
    return Result(Value, Error).Ok(Value.Bool(false))
  }
  if b == LOWER_N {
    expect_word(p, "null")?
    return Result(Value, Error).Ok(Value.Null)
  }
  if b == MINUS or is_digit_byte(b) { return parse_number(p) }
  Result(Value, Error).Err(fail(p, ErrorKind.UnexpectedByte))
}

## Enter one level of nesting, refusing past `MAX_DEPTH`.
descend := fn(in out p : Parser) -> Result(usize, Error) {
  if p.depth >= MAX_DEPTH {
    return Result(usize, Error).Err(fail(p, ErrorKind.TooDeep))
  }
  p.depth += 1
  Result(usize, Error).Ok(p.depth)
}

## After an element: consume `,` and report `true` (another element follows) or consume
## `close` and report `false`.
more := fn(in out p : Parser, close : u8) -> Result(bool, Error) {
  skip_ws(p)
  b := need(p)?
  if b == COMMA {
    p.pos += 1
    return Result(bool, Error).Ok(true)
  }
  if b == close {
    p.pos += 1
    return Result(bool, Error).Ok(false)
  }
  Result(bool, Error).Err(fail(p, ErrorKind.UnexpectedByte))
}

## Consume `close` if it comes next (after whitespace): the empty-container case.
closes_empty := fn(in out p : Parser, close : u8) -> bool {
  skip_ws(p)
  if at_byte(p, close) {
    p.pos += 1
    return true
  }
  false
}

parse_array := fn(in out p : Parser) -> Result(Value, Error) {
  descend(p)?
  p.pos += 1
  mut xs := alloc::vec::new(Value, p.a)
  if closes_empty(p, RBRACKET) == false {
    mut go := true
    while go {
      ## blocked-by: #1160, #1161 — neither `v := parse_value(p)?` nor a bound `match` with a
      ## `return` arm compiles, so the value is used inside the `Ok` arm.
      match parse_value(p) {
        Ok(v) => {
          ## blocked-by: #1163 — a method-syntax call to a generic `alloc::vec` fn names its instance
          ## after an argument's spelling (link failure or a crash), so the type is passed explicitly.
          room(p, alloc::vec::push(Value, xs, v))?
        }
        Err(e) => {
          return Result(Value, Error).Err(e)
        }
      }
      go = more(p, RBRACKET)?
    }
  }
  p.depth -= 1
  Result(Value, Error).Ok(Value.Arr(xs))
}

parse_object := fn(in out p : Parser) -> Result(Value, Error) {
  descend(p)?
  p.pos += 1
  mut ms := alloc::vec::new(Member, p.a)
  if closes_empty(p, RBRACE) == false {
    mut go := true
    while go {
      skip_ws(p)
      if need(p)? != QUOTE {
        return Result(Value, Error).Err(fail(p, ErrorKind.UnexpectedByte))
      }
      ## blocked-by: #1160, #1161 — neither `key := parse_string(p)?` nor a bound `match`
      ## with a `return` arm compiles, so the key and value are used inside the `Ok` arms.
      match parse_string(p) {
        Ok(key) => {
          skip_ws(p)
          if need(p)? != COLON {
            return Result(Value, Error).Err(fail(p, ErrorKind.UnexpectedByte))
          }
          p.pos += 1
          match parse_value(p) {
            Ok(v) => {
              ## blocked-by: #1163 — a method-syntax call to a generic `alloc::vec` fn names its instance
              ## after an argument's spelling (link failure or a crash), so the type is passed explicitly.
              room(p, alloc::vec::push(Member, ms, Member(key = key, val = v)))?
            }
            Err(e) => {
              return Result(Value, Error).Err(e)
            }
          }
        }
        Err(e) => {
          return Result(Value, Error).Err(e)
        }
      }
      go = more(p, RBRACE)?
    }
  }
  p.depth -= 1
  Result(Value, Error).Ok(Value.Obj(ms))
}

## The value of the hex digit under the cursor.
hex_digit := fn(in p : Parser) -> Result(u32, Error) {
  b := need(p)?
  if b >= 0x30 and b <= 0x39 { return Result(u32, Error).Ok(u32(b - 0x30)) }
  if b >= 0x41 and b <= 0x46 { return Result(u32, Error).Ok(u32(b - 0x41) + 10) }
  if b >= 0x61 and b <= 0x66 { return Result(u32, Error).Ok(u32(b - 0x61) + 10) }
  Result(u32, Error).Err(fail(p, ErrorKind.BadEscape))
}

## The four hex digits after `\u`; the cursor is on the first digit.
read_hex4 := fn(in out p : Parser) -> Result(u32, Error) {
  mut v : u32 = 0
  for _ in 0..4 {
    v = v * 16 + hex_digit(p)?
    p.pos += 1
  }
  Result(u32, Error).Ok(v)
}

## The code point of a `\u` escape, joining a surrogate pair. The cursor is on the `u`;
## an unpaired surrogate is a `BadEscape` at the escape's backslash.
read_unicode := fn(in out p : Parser) -> Result(u32, Error) {
  start := p.pos - 1
  p.pos += 1
  hi := read_hex4(p)?
  if hi >= 0xDC00 and hi <= 0xDFFF {
    p.pos = start
    return Result(u32, Error).Err(fail(p, ErrorKind.BadEscape))
  }
  if hi < 0xD800 or hi > 0xDBFF {
    return Result(u32, Error).Ok(hi)
  }
  if at_byte(p, BACKSLASH) == false or p.pos + 1 >= p.src.len or p.src[p.pos + 1] != LOWER_U {
    p.pos = start
    return Result(u32, Error).Err(fail(p, ErrorKind.BadEscape))
  }
  p.pos += 2
  lo := read_hex4(p)?
  if lo < 0xDC00 or lo > 0xDFFF {
    p.pos = start
    return Result(u32, Error).Err(fail(p, ErrorKind.BadEscape))
  }
  Result(u32, Error).Ok(0x10000 + (hi - 0xD800) * 0x400 + (lo - 0xDC00))
}

## Append the text a one-letter escape stands for. The cursor is on the letter; an
## unknown letter is a `BadEscape` at the escape's backslash.
put_escape := fn(in out p : Parser, in out out : String, b : u8) -> Result(usize, Error) {
  mut t : str = ""
  if b == QUOTE { t = "\"" }
  else if b == BACKSLASH { t = "\\" }
  else if b == SLASH { t = "/" }
  else if b == LOWER_B { t = "\x08" }
  else if b == LOWER_F { t = "\x0c" }
  else if b == LOWER_N { t = "\n" }
  else if b == LOWER_R { t = "\r" }
  else if b == LOWER_T { t = "\t" }
  else {
    p.pos -= 1
    return Result(usize, Error).Err(fail(p, ErrorKind.BadEscape))
  }
  room(p, put(out, t))
}

## Append `s` to `out`.
put := fn(in out out : String, s : str) -> Result(usize, AllocError) {
  ## blocked-by: #1158 — `out.push_str(s)` on a `String` is refused as "invalid".
  alloc::string::push_str(out, s)
}

## A string literal, decoded into a fresh arena string. The cursor is on the opening `"`.
parse_string := fn(in out p : Parser) -> Result(str, Error) {
  mut out := alloc::string::new(p.a)
  match decode_string(p, out) {
    Ok(_) => {
      Result(str, Error).Ok(alloc::string::as_str(ptr(out)))
    }
    Err(e) => {
      alloc::string::free(out)
      Result(str, Error).Err(e)
    }
  }
}

## Decode the string literal under the cursor into `out`, leaving the cursor after its
## closing quote. Runs of plain bytes are copied as slices of the input.
decode_string := fn(in out p : Parser, in out out : String) -> Result(usize, Error) {
  p.pos += 1
  ## blocked-by: #1162 — a local named like a fn in the consuming package's root is refused,
  ## so the run start is `from`, not `run`.
  mut from := p.pos
  mut b := need(p)?
  while b != QUOTE {
    if b < SPACE {
      return Result(usize, Error).Err(fail(p, ErrorKind.ControlInString))
    }
    if b == BACKSLASH {
      room(p, put(out, p.text[from..p.pos]))?
      p.pos += 1
      e := need(p)?
      if e == LOWER_U {
        cp := read_unicode(p)?
        room(p, push_code_point(out, cp))?
      } else {
        put_escape(p, out, e)?
        p.pos += 1
      }
      from = p.pos
    } else {
      p.pos += 1
    }
    b = need(p)?
  }
  room(p, put(out, p.text[from..p.pos]))?
  p.pos += 1
  Result(usize, Error).Ok(alloc::string::len(ptr(out)))
}

## Append the code point `cp` (a scalar value: `read_unicode` refuses lone surrogates).
push_code_point := fn(in out out : String, cp : u32) -> Result(usize, AllocError) {
  ## blocked-by: #607 — `char(cp)` fails at link unless the program names `base::char`
  ## elsewhere; this call is that mention.
  if base::char::is_digit(char(0x30)) == false { return Result(usize, AllocError).Ok(0) }
  ## blocked-by: #1158 — `out.push(c)` on a `String` is refused as "invalid".
  alloc::string::push(out, char(cp))
}

## Whether `b` is an ASCII decimal digit.
is_digit_byte := fn(b : u8) -> bool {
  b >= DIGIT0 and b <= DIGIT9
}

## Scan the digits under the cursor, folding them into `mag` (saturating: `fits` turns
## false once the value no longer fits `u64`) and into the float mantissa `m`. Returns
## how many digits were read.
Digits := struct {
  count : usize,
  mag : u64,
  fits : bool,
  m : f64,
}

scan_digits := fn(in out p : Parser, in out d : Digits) {
  while p.pos < p.src.len and is_digit_byte(p.src[p.pos]) {
    k := u64(p.src[p.pos] - DIGIT0)
    if d.fits {
      if d.mag > (18446744073709551615 - k) / 10 {
        d.fits = false
      } else {
        d.mag = d.mag * 10 + k
      }
    }
    d.m = d.m * 10.0 + f64(k)
    d.count += 1
    p.pos += 1
  }
}

## `m * 10^e`, by repeated scaling.
scale10 := fn(m : f64, e : i64) -> f64 {
  mut v : f64 = m
  mut k : i64 = e
  while k > 0 {
    v = v * 10.0
    k -= 1
  }
  while k < 0 {
    v = v / 10.0
    k += 1
  }
  v
}

## The magnitude of `i64`'s minimum, one past its maximum.
I64_MIN_MAG : u64 = 9223372036854775808

parse_number := fn(in out p : Parser) -> Result(Value, Error) {
  start := p.pos
  neg := p.src[p.pos] == MINUS
  if neg { p.pos += 1 }
  mut d := Digits(count = 0, mag = 0, fits = true, m = 0.0)
  b := need(p)?
  if is_digit_byte(b) == false {
    return Result(Value, Error).Err(fail(p, ErrorKind.BadNumber))
  }
  if b == DIGIT0 {
    p.pos += 1
    d.count = 1
    if p.pos < p.src.len and is_digit_byte(p.src[p.pos]) {
      return Result(Value, Error).Err(fail(p, ErrorKind.BadNumber))
    }
  } else {
    scan_digits(p, d)
  }
  mut integral := true
  mut frac_digits : usize = 0
  if at_byte(p, DOT) {
    integral = false
    p.pos += 1
    before := d.count
    scan_digits(p, d)
    frac_digits = d.count - before
    if frac_digits == 0 {
      return Result(Value, Error).Err(fail(p, ErrorKind.BadNumber))
    }
  }
  mut exp : i64 = 0
  if at_byte(p, LOWER_E) or at_byte(p, UPPER_E) {
    integral = false
    p.pos += 1
    mut exp_neg := false
    if at_byte(p, PLUS) or at_byte(p, MINUS) {
      exp_neg = at_byte(p, MINUS)
      p.pos += 1
    }
    mut e := Digits(count = 0, mag = 0, fits = true, m = 0.0)
    scan_digits(p, e)
    if e.count == 0 {
      return Result(Value, Error).Err(fail(p, ErrorKind.BadNumber))
    }
    ## An exponent past any f64's range saturates; 400 is already beyond it.
    mut em : i64 = 400
    if e.fits and e.mag < 400 { em = i64(e.mag) }
    exp = if exp_neg { 0 - em } else { em }
  }
  if integral and d.fits {
    if neg == false and d.mag < I64_MIN_MAG {
      return Result(Value, Error).Ok(Value.Int(i64(d.mag)))
    }
    if neg and d.mag < I64_MIN_MAG {
      return Result(Value, Error).Ok(Value.Int(0 - i64(d.mag)))
    }
    if neg and d.mag == I64_MIN_MAG {
      return Result(Value, Error).Ok(Value.Int(0 - i64(I64_MIN_MAG - 1) - 1))
    }
  }
  x := scale10(d.m, exp - i64(frac_digits))
  Result(Value, Error).Ok(Value.Float(if neg { 0.0 - x } else { x }))
}

## Render `v` as compact JSON text (no whitespace between tokens) into a new arena string.
## A non-finite `Float` (which `parse` never produces) renders as `null`, the one JSON
## value that does not claim a number.
pub render := fn(a : ptr(mut Arena), v : Value) -> Result(String, AllocError) {
  mut out := alloc::string::new(a)
  match emit(out, v) {
    Ok(_) => {
      Result(String, AllocError).Ok(out)
    }
    Err(e) => {
      alloc::string::free(out)
      Result(String, AllocError).Err(e)
    }
  }
}

emit := fn(in out out : String, v : Value) -> Result(usize, AllocError) {
  match v {
    Value.Null => {
      put(out, "null")?
    }
    Value.Bool(b) => {
      put(out, if b { "true" } else { "false" })?
    }
    Value.Int(n) => {
      alloc::fmt::display(i64, n, out)?
    }
    Value.Float(x) => {
      emit_float(out, x)?
    }
    Value.Str(s) => {
      emit_string(out, s)?
    }
    Value.Arr(xs) => {
      put(out, "[")?
      mut first := true
      ## blocked-by: #1163 — a method-syntax call to a generic `alloc::vec` fn names its instance
      ## after an argument's spelling (link failure or a crash), so the type is passed explicitly.
      for x in alloc::vec::iter(Value, ptr(xs)) {
        if first == false { put(out, ",")? }
        first = false
        emit(out, x)?
      }
      put(out, "]")?
    }
    Value.Obj(ms) => {
      put(out, "{")?
      mut first := true
      ## blocked-by: #1163 — a method-syntax call to a generic `alloc::vec` fn names its instance
      ## after an argument's spelling (link failure or a crash), so the type is passed explicitly.
      for m in alloc::vec::iter(Member, ptr(ms)) {
        if first == false { put(out, ",")? }
        first = false
        emit_string(out, m.key)?
        put(out, ":")?
        emit(out, m.val)?
      }
      put(out, "}")?
    }
  }
  Result(usize, AllocError).Ok(alloc::string::len(ptr(out)))
}

## A float in a form `parse` reads back as a `Float`: plain decimal for magnitudes in
## [1e-4, 1e15), otherwise `<mantissa>e<exponent>` with the mantissa in [1, 10). The
## fractional part is the stdlib's bounded six digits (Stdlib appendix §2.3, the interim
## float layer), so a value with more significant digits round-trips approximately.
emit_float := fn(in out out : String, x : f64) -> Result(usize, AllocError) {
  if x != x or x - x != 0.0 {
    return put(out, "null")
  }
  mut v : f64 = x
  if v < 0.0 {
    put(out, "-")?
    v = 0.0 - v
  }
  if v == 0.0 or (v >= 0.0001 and v < 1000000000000000.0) {
    return alloc::fmt::display(f64, v, out)
  }
  mut e : i64 = 0
  while v >= 10.0 {
    v = v / 10.0
    e += 1
  }
  while v < 1.0 {
    v = v * 10.0
    e -= 1
  }
  alloc::fmt::display(f64, v, out)?
  put(out, "e")?
  alloc::fmt::display(i64, e, out)
}

## Lowercase hex digits, indexed by value.
HEX : str = "0123456789abcdef"

## A string literal: `"` and `\` escaped, control bytes as their short escape or `\u00XX`,
## everything else (including non-ASCII UTF-8) copied through in runs.
emit_string := fn(in out out : String, s : str) -> Result(usize, AllocError) {
  put(out, "\"")?
  bs := bytes(s)
  ## blocked-by: #1162 — a local named like a fn in the consuming package's root is refused,
  ## so the run start is `from`, not `run`.
  mut from : usize = 0
  mut i : usize = 0
  while i < bs.len {
    b := bs[i]
    if b == QUOTE or b == BACKSLASH or b < SPACE {
      put(out, s[from..i])?
      if b == QUOTE {
        put(out, "\\\"")?
      } else if b == BACKSLASH {
        put(out, "\\\\")?
      } else if b == LF {
        put(out, "\\n")?
      } else if b == CR {
        put(out, "\\r")?
      } else if b == TAB {
        put(out, "\\t")?
      } else if b == BACKSPACE {
        put(out, "\\b")?
      } else if b == FORMFEED {
        put(out, "\\f")?
      } else {
        put(out, "\\u00")?
        hi := usize(b / 16)
        lo := usize(b & 0x0F)
        put(out, HEX[hi..hi + 1])?
        put(out, HEX[lo..lo + 1])?
      }
      from = i + 1
    }
    i += 1
  }
  put(out, s[from..bs.len])?
  put(out, "\"")
}
