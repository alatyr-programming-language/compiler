- **The container matrix tells a crash from a trap (#1277).** Only the checked-failure `ud2` (rc 132)
  is a `TRAP`; a segfault, any other signal, a timeout or a stray exit code is now `CRASH <rc>`, held
  like `WRONG`. At main `cf159743` this exposes 17 crash cells, all segfaults, now rows under #987
  (10), #1256 (5) and #1608 (2); a planted segfault is proved to turn the gate red.
