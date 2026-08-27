#!/usr/bin/env python3
"""Seed the IT'S SAXY fixture bundle into a bundle store (INTEGRATION.md §5.1).

    python scripts/seed_its_saxy_store.py file:///path/to/bundles

Prints the entry URI the consumer posts back. Idempotent: run it twice and the second
run reports the entry the first one wrote, because nothing in `mediacore` overwrites an
entry. The work is `mediacore.seed_its_saxy_store`, which ships in the package — the
other repos' dev stacks install the wheel and call that directly rather than this file.
"""

from __future__ import annotations

import sys

from mediacore import seed_its_saxy_store

USAGE = "usage: seed_its_saxy_store.py <store uri>   e.g. file:///path/to/bundles"
EXPECTED_ARGUMENT_COUNT = 2
STORE_URI_ARGUMENT_INDEX = 1
USAGE_EXIT_CODE = 2


def main(argv: list[str]) -> int:
    if len(argv) != EXPECTED_ARGUMENT_COUNT:
        print(USAGE, file=sys.stderr)
        return USAGE_EXIT_CODE
    entry = seed_its_saxy_store(argv[STORE_URI_ARGUMENT_INDEX])
    print(entry.uri)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
