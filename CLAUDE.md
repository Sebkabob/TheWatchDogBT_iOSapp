## App Version

**Current: V1.0.0**  (last reconciled at commit `16a2a5d`)

Format: `V<MAJOR>.<MAIN>.<V2>` — single source of truth lives in
`AppVersion.swift` (`AppVersion.major/main/v2`, plus `displayString`). This
line in CLAUDE.md and the Swift constants **must stay in sync**.

Bump rules:

| Field | When to bump |
|-------|--------------|
| `MAJOR` | Manual only — Sebastian explicitly asks. Reset `MAIN` and `V2` to `0`. |
| `MAIN`  | +1 for every commit that lands on `main`. Reset `V2` to `0`. |
| `V2`    | +1 for every commit that lands on `V2`. |

**Claude — do this every session, before any other work:**

1. Read the "last reconciled at commit `<sha>`" marker on the line above.
2. Run `git log --oneline <sha>..HEAD` on **both** `main` and `V2`.
3. Apply bumps in order: each `main` commit → +1 `MAIN` (reset `V2` to 0);
   each `V2` commit → +1 `V2`. Skip merges if both parents are counted.
4. If anything bumped: update `AppVersion.major/main/v2` AND the "Current"
   line + reconciled-sha above, in the same edit. Commit message style:
   `version bump to Vx.y.z`.
5. If nothing landed: do nothing.

**When the user asks you to commit/push:** also bump for the commit you're
about to make, in the same commit. Don't bump for amends, rebases, or
local-only WIP commits unless told to.

When in doubt about which branch a commit will land on, ask.
