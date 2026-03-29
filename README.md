# Codewake

<img src="docs/icon.png" alt="" width="104" align="right">

A native macOS app that treats a Git repository's history as a timeline you can scrub.
Drag the playhead and watch the codebase change: files appear, directories grow, hotspots
heat up, the files that secretly change together light up, and the parts of the codebase
only one person has ever touched show themselves.

![Codewake showing a repository's hotspot map](docs/screenshot.png)

## Why

Git is good at telling you *what* changed and *when*. It is much worse at telling you
where the risk lives. A file that is large, tangled, and edited every week is the one most
likely to break when you touch it, but nothing in `git log` puts that in front of you.

Codewake computes hotspots (churn × complexity), change coupling, and ownership at every
point in a repository's history, and draws them as a map you can scrub through time.

## Installing

Download `Codewake.zip` from the [latest release](../../releases/latest), unzip it, and drag
`Codewake.app` to your Applications folder. It is a universal binary and needs macOS 15 or
later.

The app is signed **ad-hoc**, not with a paid Apple Developer ID, so macOS quarantines it on
first launch and refuses to open it. Either:

```sh
xattr -dr com.apple.quarantine /Applications/Codewake.app
```

or open it once, then go to **System Settings → Privacy & Security**, scroll to the bottom
and click **Open Anyway**. macOS only asks once.

### From source

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

To build the bundle yourself:

```sh
./Scripts/bundle.sh                  # universal, into dist/
ARCHS=arm64 ./Scripts/bundle.sh      # this machine only, much faster
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
| `⌘1` … `⌘4` | Switch between the map, ownership, age, and coupling |
| `⌘F` | Filter files — matches stay lit, everything else dims |
| Click a folder's name | Open it — its files get the whole canvas |
| `Esc` | Clear the search, the author, the selection, then step back out |

## What it shows

**The map** — every file that exists at the current moment, sized by length, coloured by
hotspot score, grouped by top-level directory. Selecting a file outlines the files it
usually changes with, so a hidden cluster becomes visible at a glance. Clicking a folder's
name opens it, handing its contents the whole canvas; hovering a rectangle too small to
carry a name magnifies the area around it.

**The ownership map** — the same rectangles, coloured by whoever has the most commits to
each file, and faded toward grey where no one person has a real claim on it. Blocks of one
colour are the parts of the codebase a single person holds. The panel beside it counts how
much of the code has only ever been touched by one person, and how few people it would take
to lose half of it.

![The ownership map, coloured by who owns each file](docs/ownership.png)

**The age map** — the same rectangles again, coloured by how long it has been since anyone
touched each file. Bright is where the work is; dark is code nobody has had a reason to
open, which is either the stable foundation or the part everyone is afraid of. Scrubbing
makes the point better than a screenshot can: play the history and watch the codebase cool
behind the playhead as the work moves on.

![The age map, dark where the codebase has stopped moving](docs/age.png)

**The coupling map** — every group of files that changes together, drawn as a constellation
per group. The inspector answers this for one file, but only once you have guessed which
file to click; this is the same fact without the guess. Not a treemap, deliberately: the
other three views are about a property each file has, and this one is about a relation
between files, which rectangles cannot draw.

![The coupling map, one constellation per group of files that change together](docs/coupling.png)

**The inspector** — for the selected file at the selected moment: its size, its churn, its
nesting depth, who has touched it, what it changes with, and how its churn was distributed
over time.

## How it works

```
git log ──▶ parse ──▶ file timelines ──▶ snapshot engine ──▶ hotspots ──▶ map
                                               │           └─▶ coupling ──▶ outlines
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

**Coupling needs no index — until you ask about all of it.** Finding what a file changes with looks like it needs a
precomputed table of every file pair, which is expensive to build and to keep correct
while scrubbing. It does not: a file's own event list already names every commit that
touched it, and each of those commits already names every other file it touched. Walking
that costs a pass over one file's history, so coupling is answered on demand for whatever
was just clicked. Asked about the whole snapshot there is no file to start from, so the
coupling view does build the pair table — but only over the commits actually scrubbed
through, and only over commits small enough to mean something, which caps what any one
commit can contribute at a few hundred pairs however large the repository is. Commits
touching more than 25 files are ignored throughout — a mass rename couples everything to
everything and means nothing.

Strength is measured against the rarer of the two files rather than the busier one. A file
touched in nearly every commit would otherwise look coupled to the entire codebase, when
what it is, is busy.

**Ownership is counted in commits, not surviving lines.** `git blame` answers "whose lines
are these right now", which is the fragile version of the question: one reformat or one
rename rewrites every line's author without moving any knowledge. Who keeps coming back to
change a file is the durable signal, and it falls straight out of the history already
parsed. Unlike coupling, it cannot be answered for one file on demand — the question is
about the shape of the whole codebase — so it walks every live file's applied events, which
is why the app runs it once the playhead settles and caches the answer per position rather
than on every frame.

**Complexity is measured lazily and cached by blob SHA.** Reading file contents is the only
expensive operation, so it happens only for the top files by churn, only once the playhead
stops moving, and never twice for the same content. During a drag the view scores files
using size as a stand-in and refines once you let go.

## Performance

Two repositories, four orders of magnitude apart. The first is a 1,836-commit application;
the second is git's own history, at 60,896 non-merge commits (82,154 including merges),
5,004 files and 1.6M lines.

| Operation | 1,836 commits | 60,896 commits |
| --- | --- | --- |
| Load and index | 0.62s | 25s † |
| Scrub step (cached) | 0.05ms | 0.17ms † |
| Repository-wide ownership | 1ms | 16ms † |
| Repository-wide file age | 1.0ms | — |
| Coupling clusters, whole snapshot | 0.9ms | — |
| Treemap layout, 250 tiles | 0.37ms | 0.16ms † |
| First complexity measurement | 0.15s | 0.83s † |
| Repeat measurement (cached) | 0.21ms | 0.49ms † |
| Memory, resident | 18 MB | 159 MB † |

† Measured on an earlier build and not re-run since. Load got faster when the branch view
was removed — that was a second `git log` pass — and the treemap gained a pass of its own,
so the figures marked will have moved. They are left in because the shape of the answer is
what the column is for, and the shape has not changed. The age view was added after that
run and has only been measured on the smaller repository.

Everything that happens while the app is open stays far inside a frame at both sizes, and
memory grows roughly with the number of file events rather than with the number of commits.

**Loading is the one thing that does not scale, and it is not Codewake's code.** Of the 25
seconds, 23.5 are `git log --raw --numstat` producing 28 MB of output; parsing that costs
0.21s and building the file timelines another 0.2s. Making a large repository open quickly
would mean not reading its whole history up front — loading around the playhead, or caching
a parsed history on disk — rather than optimising anything in the current path.

Reproduce with `CODEWAKE_BENCH_REPO=~/some/repo swift test -c release --filter BenchmarkTests`.

## Tests

```sh
swift test
```

77 tests covering the log parser against real git output (renames, binary files,
deletions, awkward commit subjects), the snapshot engine's forward/backward equivalence,
coupling thresholds and cluster extraction, ownership and bus factor as the playhead
moves, file age across scrubs and renames, complexity scoring, treemap geometry including that no file is ever
too small to be drawn, and an end-to-end pass over a repository the test builds itself.

GitHub Actions runs the same tests on every push, then builds and signs `Codewake.app` and
attaches it to any tagged release.

## Limitations

Complexity is a proxy, not a parse. Only the current branch's history is read, so work
that never landed on it does not appear. Merge commits are skipped when counting churn, so
work is not counted twice. Authors are identified by the name on the commit, so one person
committing under two names counts as two people. There is no architecture or dependency
view.

Opening a very large repository takes about half a minute, almost all of it spent waiting
for `git log` — see Performance.

A hotspot is a question, not a verdict — it says where to look, not what is wrong.

## License

MIT
