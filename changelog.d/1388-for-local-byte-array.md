- **`for x in t` over a local `[u8; N]` or `[i8; N]` array yields its elements (#1388).** On x86_64
  the loop read the packed bytes' first word as a data pointer and died with SIGSEGV.
