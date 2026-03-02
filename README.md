# Codewake

A native macOS app that treats a Git repository's history as a timeline you can scrub.
Drag the playhead and watch the codebase change: files appear, directories grow, hotspots
heat up, and the files that secretly change together light up.

![Codewake showing a repository's hotspot map](docs/screenshot.png)

## Why

Git is good at telling you *what* changed and *when*. It is much worse at telling you
where the risk lives. A file that is large, tangled, and edited every week is the one most
likely to break when you touch it, but nothing in `git log` puts that in front of you.

Codewake computes hotspots (churn × complexity) and change coupling at every point in a
repository's history, and draws them as a map you can scrub through time.

## Running it

Requires macOS 15+ and Xcode 16+ (built against Swift 6.3).

```sh
swift run codewake
```

Then open any local repository. To skip the picker:

```sh
swift run codewake -repo ~/some/repo
# or
CODEWAKE_REPO=~/some/repo swift run codewake
```

If you are new to these metrics, the **?** button in the toolbar (or `⌘/`) explains every
term the interface uses.

### Controls

| | |
| --- | --- |
| Drag the timeline | Move through history |
| `←` `→` | Step one commit |
| `Space` / `⌘P` | Play or pause |
| `⌘⌥←` `⌘⌥→` | Jump to the first or last commit |
| `⌘1` `⌘2` | Switch between the map and branches |
| `⌘F` | Filter files — matches stay lit, everything else dims |
| `Esc` | Clear the search, then the selection |

## What it shows

**The map** — every file that exists at the current moment, sized by length, coloured by
hotspot score, grouped by top-level directory. Selecting a file outlines the files it
usually changes with, so a hidden cluster becomes visible at a glance.

**The branches view** — every merged branch as a bar from its first commit to the day it
landed, coloured by how much code it moved. Selecting one moves the playhead to where its
work arrived.

**The inspector** — for the selected file at the selected moment: its size, its churn, its
nesting depth, who has touched it, what it changes with, and how its churn was distributed
over time.

## How it works

```
git log ──▶ parse ──▶ file timelines ──▶ snapshot engine ──▶ hotspots ──▶ map
        └─▶ graph ──▶ branch extraction        │           └─▶ coupling ──▶ outlines
                                               ▲
                                          scrub position
```

`CodewakeKit` holds all of it and imports no UI framework, so every part is testable
without a window. The app target is just views over that engine.

A few decisions that carry the project:

**One pass over history, then never git again for churn.** A single
`git log --raw --numstat -M` gives per-commit line counts, rename tracking, *and* the
post-image blob SHA of every change. That last part removes a whole subsystem: because
each file event records its own blob, the contents of any file at any point in history are
reachable without walking trees.

**Scrubbing is incremental, in both directions.** The snapshot engine holds the repository
state at commit `i`; moving to `j` applies or unapplies only the commits in between, so
cost scales with the size of the jump rather than the size of the repository. Every
quantity it tracks is either additive or a count of applied events, which makes stepping
backwards exactly as cheap and exactly as accurate as stepping forwards — there is no undo
log. A property test asserts that scrubbing to a position from either direction produces
identical state.

**Coupling needs no index.** Finding what a file changes with looks like it needs a
precomputed table of every file pair, which is expensive to build and to keep correct
while scrubbing. It does not: a file's own event list already names every commit that
touched it, and each of those commits already names every other file it touched. Walking
that costs a pass over one file's history, so coupling is answered on demand for whatever
was just clicked. Commits touching more than 25 files are ignored — a mass rename couples
everything to everything and means nothing.

**Branches are reconstructed from the graph, not from ref names.** Topic branches are
usually deleted after merging, so their names survive only in the message git wrote. The
first-parent chain from HEAD is the trunk; commits reachable from a merge's other parents
but not from the trunk are exactly the work that happened on a branch. One extra `git log`
pass, no `rev-list` per merge. On a real 566-merge repository this recovers 277 branches
with their names, durations, authors, and sizes.

**Complexity is measured lazily and cached by blob SHA.** Reading file contents is the only
expensive operation, so it happens only for the top files by churn, only once the playhead
stops moving, and never twice for the same content. During a drag the view scores files
using size as a stand-in and refines once you let go.

## Performance

Measured on a real 1,836-commit, 881-file repository with 566 merges:

| Operation | Time |
| --- | --- |
| Load, index, and extract branches | 0.91s |
| Scrub step (cached) | 1.12ms |
| First complexity measurement | 0.28s |
| Repeat measurement (cached) | 2.2ms |

Reproduce with `CODEWAKE_BENCH_REPO=~/some/repo swift test --filter BenchmarkTests`.

## Tests

```sh
swift test
```

61 tests covering the log parser against real git output (renames, binary files,
deletions, awkward commit subjects), the snapshot engine's forward/backward equivalence,
coupling thresholds, branch extraction including back-merges and double-counting,
complexity scoring, treemap geometry, and an end-to-end pass over a repository the test
builds itself.

## Limitations

Complexity is a proxy, not a parse. Only the current branch's history is read, so branches
that were never merged do not appear. Merge commits are skipped when counting churn, so
work is not counted twice. Ownership is reported per file but there is no repository-wide
ownership view yet, and there is no architecture or dependency view.

A hotspot is a question, not a verdict — it says where to look, not what is wrong.

## License

MIT
