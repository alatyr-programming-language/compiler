## e2e — std::path POSIX decomposition (all allocation-free str VIEWs). Exercises basename/dirname/
## extension/stem/is_absolute across the tricky cases: a normal path, a root-level file, a dotless name,
## a trailing slash, and a leading-dot (extension-less) name. Returns 42 iff every case is exact.
pa := std::path

main := fn() -> u64 {
  if not (pa::basename("/usr/lib/foo.txt") == "foo.txt") { return 1 }
  if not (pa::basename("abc") == "abc") { return 2 }
  if not (pa::basename("/a/b/") == "") { return 3 }
  if not (pa::dirname("/usr/lib/foo.txt") == "/usr/lib") { return 4 }
  if not (pa::dirname("/a") == "/") { return 5 }
  if not (pa::dirname("abc") == ".") { return 6 }
  if not (pa::extension("/usr/lib/foo.txt") == "txt") { return 7 }
  if not (pa::extension("archive.tar.gz") == "gz") { return 8 }
  if not (pa::extension("noext") == "") { return 9 }
  if not (pa::extension(".bashrc") == "") { return 10 }
  if not (pa::stem("/usr/lib/foo.txt") == "foo") { return 11 }
  if not (pa::stem(".bashrc") == ".bashrc") { return 12 }
  if not pa::is_absolute("/etc") { return 13 }
  if pa::is_absolute("rel/path") { return 14 }
  return 42
}
