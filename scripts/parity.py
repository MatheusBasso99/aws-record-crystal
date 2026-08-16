#!/usr/bin/env python3
"""Audits spec parity with the Ruby gem (gate 4 of CLAUDE.md).

Every RSpec `it` description in ../aws-record-ruby/spec must exist verbatim as a Crystal `it`
description in the matching spec file, and every Cucumber `Scenario:` name in
../aws-record-ruby/features must exist verbatim as an `it` description under spec/integration.

Usage: scripts/parity.py [path/to/aws-record-ruby]   (default: ../aws-record-ruby)
Exits non-zero when anything is missing.
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUBY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "aws-record-ruby"))

# `it 'a ' \` + newline + `'b'` is one description; the same continuation exists in the Crystal specs.
CONTINUED = re.compile(r"(['\"])\s*\\\s*\n\s*(['\"])")
RUBY_IT = re.compile(r"^\s*it\s+(['\"])(.*?)(?<!\\)\1", re.M | re.S)
CRYSTAL_IT = re.compile(r'^\s*it\s+"(.*?)(?<!\\)"', re.M | re.S)


def descriptions(path, pattern, group):
    """Reads *path* and returns the joined `it` descriptions it declares."""
    if not os.path.exists(path):
        return []
    text = CONTINUED.sub("", open(path).read())
    return [match.group(group) for match in pattern.finditer(text)]


def report(kind, pairs):
    """Prints the audit of (label, expected, actual) triples and returns the number missing."""
    missing = total = 0
    for label, expected, actual in pairs:
        total += len(expected)
        for description in expected:
            if description not in actual:
                missing += 1
                print("  MISSING in %s: %s" % (label, description))
    print("%s: %d/%d matched" % (kind, total - missing, total))
    return missing


unit = []
for rb in sorted(glob.glob(os.path.join(RUBY, "spec", "**", "*_spec.rb"), recursive=True)):
    relative = os.path.relpath(rb, os.path.join(RUBY, "spec"))
    cr = os.path.join(HERE, "spec", relative.replace(".rb", ".cr"))
    unit.append((relative, descriptions(rb, RUBY_IT, 2), descriptions(cr, CRYSTAL_IT, 1)))

ported = []
for spec in sorted(glob.glob(os.path.join(HERE, "spec", "integration", "*_spec.cr"))):
    ported += descriptions(spec, CRYSTAL_IT, 1)
integration = []
for feature in sorted(glob.glob(os.path.join(RUBY, "features", "**", "*.feature"), recursive=True)):
    names = [line.split(":", 1)[1].strip() for line in open(feature) if line.strip().startswith("Scenario:")]
    integration.append((os.path.relpath(feature, os.path.join(RUBY, "features")), names, ported))

failures = report("unit examples", unit) + report("integration scenarios", integration)
sys.exit(1 if failures else 0)
