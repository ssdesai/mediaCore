# Level 3 sentinel — fixture seeding, and the whole batch

The gate runs here, labelled `10`, and this level owns everything: install, lint,
`fixture idempotent`, `wheel contains fixture`, and the whole test suite including
`tests/test_store_fixture.py`, the batch's acceptance test.

`fixture idempotent` matters at this level for a reason beyond level 1's: it fails on
any change under `fixtures/`, which is exactly what catches a seeding function that
wrote a store into the checkout instead of outside it.

No `expected-red:` and no `defer:`: a red section here is a real failure.
