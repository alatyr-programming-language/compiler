/* Issue #168 reference: C reads both fields of the Alatyr-provided argument before returning it. */
struct Pair { unsigned char a; unsigned char b; };

static long pair_code(struct Pair p) { return (long)p.a * 4L + (long)p.b * 8L; }

struct Pair echo_pair(struct Pair p) {
  if (pair_code(p) == 68L) return p;
  p.a = 0;
  p.b = 0;
  return p;
}
