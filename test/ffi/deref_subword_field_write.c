/* Issue #167 FFI witness.  The Alatyr callee receives &w.p, writes p.b, and must not touch guard. */
struct P8 { unsigned char a, b; };
struct Wrap { struct P8 p; unsigned long guard; };
extern void issue167_setb(struct P8 *p);

long drive(void) {
  struct Wrap w = {{1, 2}, 100};
  issue167_setb(&w.p);
  if (w.guard != 100) return 3;
  if (w.p.a != 1) return 4;
  if (w.p.b != 9) return 5;
  return 42;
}
