## std::path — POSIX path decomposition. Every function returns a `str` VIEW over the input bytes (no
## allocation), so they compose freely and never fail. Separator is `/` (0x2F); `.` (0x2E) delimits the
## extension. These are lexical only — they do not touch the filesystem.

## The 0-based index of the LAST byte `b` in `[s.ptr, s.ptr+s.len)`, or -1 if absent.
last_index_of := fn(s : str, b : u8) -> i64 {
  bs := bytes(s)
  mut i : usize = s.len
  while i > 0 {
    i -= 1
    if bs[i] == b { return i64(i) }
  }
  0 - 1
}

## `basename` — the final component after the last `/`. `"/a/b/c"` → `"c"`; `"abc"` → `"abc"`; a
## trailing slash (`"/a/b/"`) yields `""` (empty final component).
pub basename := fn(p : str) -> str {
  li := last_index_of(p, 47)
  if li < 0 { return p }
  start := usize(li) + 1
  q := unchecked bitcast(ptr(u8), bitcast(usize, p.ptr) + start)
  str_at(q, p.len - start)
}

## `dirname` — everything before the last `/`. `"/a/b/c"` → `"/a/b"`; `"/a"` → `"/"` (the root is kept);
## `"abc"` (no slash) → `"."` (the current directory).
pub dirname := fn(p : str) -> str {
  li := last_index_of(p, 47)
  if li < 0 { return "." }
  if li == 0 { return "/" }
  str_at(p.ptr, usize(li))
}

## `extension` — the substring after the last `.` in the BASENAME, `""` if none. A leading-dot name
## (`".bashrc"`) has NO extension (the dot is not an extension separator there); a dotless name too.
pub extension := fn(p : str) -> str {
  base := basename(p)
  di := last_index_of(base, 46)
  if di <= 0 { return str_at(base.ptr, 0) }
  start := usize(di) + 1
  q := unchecked bitcast(ptr(u8), bitcast(usize, base.ptr) + start)
  str_at(q, base.len - start)
}

## `stem` — the basename WITHOUT its extension. `"a.txt"` → `"a"`; `".bashrc"` → `".bashrc"` (leading
## dot kept); a dotless basename is returned whole.
pub stem := fn(p : str) -> str {
  base := basename(p)
  di := last_index_of(base, 46)
  if di <= 0 { return base }
  str_at(base.ptr, usize(di))
}

## `is_absolute` — does the path start at the root (`/`)?
pub is_absolute := fn(p : str) -> bool { p.len > 0 and bytes(p)[0] == 47 }
