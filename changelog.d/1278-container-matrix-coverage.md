- **The container matrix covers every container #1124 names (#1278).** It adds `omap` (key and value),
  `oset`, `map`, `strmap`, `string` and `strbuf`: 50 cells, 428 in all. At main `cf159743`
  the 8 new cells that fail are rows under #1244 (5), #1250 (1) and #1308 (2), and the self-test fails
  if a named container has no cells.
