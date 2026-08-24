## selfhost::lower_attrs — declaration/source attribute facts shared by lowering clients.
##
## These predicates recover parser-consumed markers from source spans. They are deliberately kept
## independent of code-generation state: the lowerer, interface-summary builder, and future module
## cache can all ask the same question without importing `lower.al` (which would create a cycle).
(Decl, Param) := ast
param_p := ast::param_p

## Is the fn whose NAME occupies `name_s .. name_s+name_l` marked `@inline`? The parser drops the
## marker, so recover both declaration-prefix and value-position spellings.
pub fn_is_inline := fn(src : ptr(u8), name_s : usize, name_l : usize) -> bool {
  ## VALUE position: `name := @inline fn(…)`. Walk the attribute run so `@inline` may coexist with
  ## other value-position attributes without depending on their order.
  mut v := name_s + name_l
  while str_at((src + v), 1) == " " or str_at((src + v), 1) == "\n" or str_at((src + v), 1) == "\t" or str_at((src + v), 1) == "\r" { v = v + 1 }
  if str_at((src + v), 2) == ":=" {
    v = v + 2
    mut attrs := true
    while attrs {
      while str_at((src + v), 1) == " " or str_at((src + v), 1) == "\n" or str_at((src + v), 1) == "\t" or str_at((src + v), 1) == "\r" { v = v + 1 }
      if str_at((src + v), 1) != "@" { attrs = false }
      else {
        if str_at((src + v), 7) == "@inline" {
          c := str_at((src + v + 7), 1)
          if c == "(" or c == " " or c == "\n" or c == "\t" or c == "\r" { return true }
        }
        v = v + 1
        while (str_at((src + v), 1) >= "a" and str_at((src + v), 1) <= "z") or (str_at((src + v), 1) >= "A" and str_at((src + v), 1) <= "Z") or (str_at((src + v), 1) >= "0" and str_at((src + v), 1) <= "9") or str_at((src + v), 1) == "_" { v = v + 1 }
        if str_at((src + v), 1) == "(" {
          mut depth := 1
          v = v + 1
          while depth > 0 {
            c := str_at((src + v), 1)
            if c == "\"" {
              v = v + 1
              while str_at((src + v), 1) != "\"" { v = v + 1 }
              v = v + 1
            } else if c == "(" { depth = depth + 1; v = v + 1 }
            else if c == ")" { depth = depth - 1; v = v + 1 }
            else { v = v + 1 }
          }
        }
      }
    }
  }
  ## DECLARATION prefix: preserve the existing `@inline name` / `@inline pub name` spellings.
  mut p := name_s
  mut scanning := true
  while p > 0 and scanning {
    while p > 0 and (str_at((src + p - 1), 1) == " " or str_at((src + p - 1), 1) == "\n" or str_at((src + p - 1), 1) == "\t" or str_at((src + p - 1), 1) == "\r") { p = p - 1 }
    if p >= 3 and str_at((src + p - 3), 3) == "pub" { p = p - 3 }
    else if p >= 3 and str_at((src + p - 3), 3) == "mut" { p = p - 3 }
    else if p >= 7 and str_at((src + p - 7), 7) == "@inline" { return true }
    else { scanning = false }
  }
  false
}

## Whether the declaration named at `name_s` carries the source-level `pub` visibility prefix.
## The parser consumes `pub` without adding a Decl field, so all consumers use this one source scan.
##
## TWO shapes this used to miss, both found by measurement (and both `pub` by the spec):
##   * `pub mut NAME` — a MUTABLE global's spelling (Declarations §2 puts `pub` before the whole
##     declaration, `mut` included). Requiring `pub` IMMEDIATELY before the name read the `mut` and
##     answered no, so a `pub mut` global was invisible to every consumer of this predicate. Step
##     over that marker, recovered from source exactly as `local_is_mut` does (the parser erases both).
##   * a declaration on the FIRST line of the FIRST module — it has NO whitespace before its `pub`.
##     The driver appends every module NAME and then every module SOURCE into one buffer with no
##     separator (`driver::compile_program`), so the byte before that `pub` is the tail of a module
##     name, an identifier byte. The old whitespace-before-`pub` guard therefore rejected it. A
##     preceding-token guard cannot be written here without the module's source origin, which no
##     `Decl` carries — so follow `local_is_mut`'s precedent and test the three bytes alone.
pub decl_is_pub := fn(src : ptr(u8), name_s : usize) -> bool {
  mut p := name_s
  while p > 0 {
    c := str_at((src + p - 1), 1)
    if c == " " or c == "\n" or c == "\t" or c == "\r" { p = p - 1 } else { break }
  }
  if p >= 3 and str_at((src + p - 3), 3) == "mut" {
    p = p - 3
    while p > 0 {
      c := str_at((src + p - 1), 1)
      if c == " " or c == "\n" or c == "\t" or c == "\r" { p = p - 1 } else { break }
    }
  }
  if p < 3 { return false }
  str_at((src + p - 3), 3) == "pub"
}

## Is the fn PARAMETER whose name starts at `ns` marked `comptime` (a comptime VALUE parameter,
## Comptime §10)? The parser consumes the keyword without recording it on Param.
pub param_is_comptime := fn(src : ptr(u8), ns : usize) -> bool {
  if ns < 8 { return false }
  mut p := ns
  mut scanning := true
  while p > 0 and scanning {
    c := str_at((src + p - 1), 1)
    if c == " " or c == "\n" or c == "\t" or c == "\r" { p = p - 1 }
    else { scanning = false }
  }
  if p < 8 { return false }
  str_at((src + p - 8), 8) == "comptime"
}

## Whether a parameter type span is the bare `..` rest (Functions §7.1).
pub type_is_variadic_rest := fn(src : ptr(u8), ts : usize, tl : usize) -> bool {
  tl >= 2 and str_at((src + ts), 2) == ".."
}

## Whether fn decl `d`'s LAST parameter is a comptime-variadic `...` rest. The unused arena
## parameter is retained for the existing lowerer ABI and call sites.
pub decl_is_variadic := fn(d : Decl, src : ptr(u8), a : rt::Arena) -> bool {
  if d.is_fn == false { return false }
  mut pp := d.params_head
  mut last := 0
  while pp != 0 { last = pp; pp = deref(param_p(pp)).next }
  if last == 0 { return false }
  lp := deref(param_p(last))
  type_is_variadic_rest(src, lp.ts, lp.tl)
}

## Whether fn decl `d`'s LAST parameter is a runtime slice-variadic `...T` (pmode == 3).
pub decl_is_slice_variadic := fn(d : Decl) -> bool {
  if d.is_fn == false { return false }
  mut pp := d.params_head
  mut last := 0
  while pp != 0 { last = pp; pp = deref(param_p(pp)).next }
  if last == 0 { return false }
  deref(param_p(last)).pmode == 3
}
