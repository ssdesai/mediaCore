# <Feature title>

<One paragraph: what this feature delivers and why the work exists. No plan-level
detail — that's what the table below is for.>

## Plans

| Plan | What it does |
|---|---|
| `auto/incomplete/NN-description-MODEL.md` | <one line> |
| `verify/incomplete/NN-verify-MODEL.md` | <one line> |
| `review/incomplete/NN-review-opus.md` | <one line> |

## Levels

| Level | Plans | Sentinel | Level-verify | Must be green |
|---|---|---|---|---|
| <1> | <NN-NN> | `NN-gate.md` | `NN-level-*-MODEL.md` or — | <gate sections> |

Delete this section when the batch has a single level.

## Contracts across levels

| Value / identifier | Produced by (plan, file:line) | Consumed by (plan, file:line) | Fixture | Asserted by |
|---|---|---|---|---|
| <name> | <NN, path:line> | <NN, path:line> | `tests/fixtures/contracts/<name>.json` or — | <producer test> / <consumer test> |

An allowed-actions contract (state × action) is one row per cell, not one row. A row
whose Fixture is `—` needs a reason in the Deliberately-excluded list below.

Delete this section when the batch has a single level.


## Deliberately excluded

- <Something that looked in-scope but isn't — and why.>

## Machine-readable

```json
{
  "slug": "<feature-slug>",
  "plans": ["NN-description-MODEL", "NN-verify-MODEL", "NN-review-opus"],
  "branches": ["<branch-name>"],
  "session_window": {"from": "<YYYY-MM-DDTHH:MM:SSZ>", "to": "<YYYY-MM-DDTHH:MM:SSZ>"},
  "exclude_sessions": ["<session-id>"]
}
```

Every field is required. These are the ones that go wrong quietly:

- **`branches`** — copy each name from `git branch --show-current`, verbatim. It is
  matched literally against the `gitBranch` in every session transcript, so an added
  owner prefix, or a name retyped from memory, matches nothing and leaves every session
  on it uncounted — the feature then reports `$0.00`, which reads as "planning was free"
  rather than "this manifest is wrong". `analysis/capture_planning.py` warns when a
  declared branch matches no transcript. If a branch was renamed mid-feature, list both
  names: transcripts keep whatever name was current when they were written.
- **`plans`** — every plan stem in the table above, *without* the `.md` extension and
  without its queue/state path, in batch order. `analysis/report.py` prices exactly this
  list: a stem left out is a plan whose cost lands in no report, and an array left out
  entirely drops the whole feature back onto a fallback that can only see plans which
  already ran.
- **`session_window` timezone** — end every bound with `Z`. A bound with no offset is
  read as UTC, and the natural place to find a timestamp is `git log`, which prints
  **local** time — so a value copied from there and pasted bare is silently off by your
  UTC offset, four hours in US Eastern, which is enough to hand a session to the wrong
  feature. Write local time only with its offset spelled out (`2026-07-17T18:00:00-04:00`);
  `analysis/capture_planning.py` warns on any bound that states no zone.
- **`session_window.to`** — `null` means "still open", and open is the right value only
  while the feature is still being planned. Set a real bound as soon as it is done. Two
  open-ended windows on a shared branch claim each other's sessions and price the same
  planning cost twice; `analysis/capture_planning.py` warns when two manifests' branches
  *and* windows both overlap, and a `to` bound is how you answer it.
