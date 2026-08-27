"""Seed the committed IT'S SAXY bundle into a store (INTEGRATION.md §5.1 "Fixture").

Usage: `python scripts/seed_bundle_store.py <store-uri>` — a `file://` or `s3://` URI.
There is no default: a store address is a deployment decision, not something this
script should guess. Idempotent — safe to run against a store that has already been
seeded, which is why a dev stack runs it on every restart. Run by hand when setting up
a dev stack for WP7b/7c/7d; never by `plans/gate.sh`, which never writes outside the
checkout.
"""

import sys

from mediacore import StoreError, seed_its_saxy_store

USAGE = "usage: python scripts/seed_bundle_store.py <store-uri>"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(USAGE, file=sys.stderr)
        return 1
    store_uri = argv[1]
    try:
        entry = seed_its_saxy_store(store_uri)
    except StoreError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(entry.uri)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
