# 09 — review

Feature: a killed attempt's cost is recoverable from its session transcript, and
`pricing.py`'s intro tier must not apply to dates before the promotion began.

Read the diff; the gate is green on arrival and is your starting condition, not a finding.
Read the feature manifest first — it carries the measurements this batch is built on and the
six design resolutions, and a finding that re-litigates a resolved decision is noise.

Weight your attention here:

- **The `starts` date is the batch's one unverifiable input.** Everything else is checkable
  from the repo; that date came from observed billing ratios. Is it recorded honestly? Does
  anything downstream present it as confirmed? What breaks if it is wrong by a day in either
  direction?
- **Does the recovery actually read the 5m/1h split from the transcript?** Assertion 7 is
  designed to catch the flat-total mistake, but a test can be satisfied without the
  production path being right. Check the read path itself.
- **`capture_planning.py`'s refactor.** It has no test, its output is frozen into committed
  artifacts, and the two transcript facts it depends on are subtle. Did the extraction
  preserve behaviour exactly, including the sidechain flag and the no-message-id case?
- **The compatibility defaults in `report.py`.** Both corpora are entirely pre-batch. A
  missing default is a crash on every historical feature, and `--all` is the command most
  likely to hit it.
- **Is anything still claiming a killed attempt's cost is unrecoverable?**

The two things this batch deliberately does not do — corpus-wide backfill, and re-capturing
the ~33%-low `planning.json` figures — are in the manifest's exclusions with reasons. If you
think either should have been in scope, say so as an escalation rather than doing it.
