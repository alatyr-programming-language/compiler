## e2e / issue #340 — an inferred `ptr(u8)` keeps its byte pointee however much whitespace precedes `:=`.
##
## Grammar §2.5 permits any whitespace between tokens; `str`'s `ptr` view has pointee `u8` (Stdlib appendix
## §3.6), so `deref(q)` is a one-byte load (Memory §4.3). `byte_ptr_local` read a fixed 512-byte window
## from the binding's name: once `s.ptr` fell outside it, the pointee was unknown and the load was eight
## bytes wide, reading "ABCDEFGH" as one word. The gaps are the boundary's neighbours (507, 508, 509
## spaces) and an ordinary single space as the control. Each binding owns a code from 11 up; 42 means
## every load read one byte.
##
## NON-VACUOUS: at `88890003` (omen, native x86_64) the 508-space binding answered 1 where 42 is due
## (`movq` instead of `movzbq`; 507 spaces gave 42). At `dc9e18e2` every gap answers 42 on x86_64.
main := fn() -> u64 {
  s := "ABCDEFGH"
  q1 := s.ptr
  if deref(q1) != 65 { return 11 }
  q507                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           := s.ptr
  if deref(q507) != 65 { return 12 }
  q508                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            := s.ptr
  if deref(q508) != 65 { return 13 }
  q509                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             := s.ptr
  if deref(q509) != 65 { return 14 }
  42
}
## expect: run 42
