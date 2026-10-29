import re, glob
files = sorted(glob.glob("src/*.al") + glob.glob("src/*/*.al") + glob.glob("lib/**/*.al", recursive=True))
n = "expr_is_int_lit"
code, comments, other = [], [], []
for f in files:
    for i, l in enumerate(open(f).read().split("\n"), 1):
        if not re.search(r"(?<![:.\w])" + n, l): continue
        if l.lstrip().startswith("##"): comments.append("%s:%d" % (f, i))
        elif re.match(r"[ \t]*(pub[ \t]+)?" + n + r"[ \t]*:=[ \t]*fn", l): code.append("%s:%d DEFINITION" % (f, i))
        else: other.append("%s:%d %s" % (f, i, l.strip()[:60]))
print("  DEFINITION lines : %s" % code)
print("  CALL sites       : %s" % (other if other else "NONE - dead copy"))
print("  comment mentions : %d (%s)" % (len(comments), comments[:3]))
