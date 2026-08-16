# scripts/coverage_gate.py — reads kcov JSON, prints a summary, exits 1 below the gate.
import glob, json, os, sys
d = json.load(open(glob.glob("coverage/spec_runner*/coverage.json")[0]))
minimum, target = float(os.environ.get("COVERAGE_MIN", 85)), float(os.environ.get("COVERAGE_TARGET", 90))
total = float(d["percent_covered"])
files = sorted(((f["file"], float(f["percent_covered"])) for f in d["files"]), key=lambda t: t[1])
print("TOTAL line coverage: %.2f%%  (gate %.0f%%, target %.0f%%)" % (total, minimum, target))
for path, pct in files[:10]:
    print("  %6.2f%%  %s" % (pct, path))
low = [(p, c) for p, c in files if "/src/aws-record/record/" in p and c < 80]
if low:
    print("FILES BELOW 80%:", low)
sys.exit(0 if total >= minimum and not low else 1)
