# AW06 library catalog and export paging, 2026-11-10

Case `AW06` (agent-workflows stage AW-06, acceptance A08 and the workflow part of A15 of
[the packet](../../archive/agent-workflows-2026-11/ACCEPTANCE.md)). Run on branch
`feat/agent-workflows-aw-07` at `0d5cd927` (PR #446, squash-merged to main as `009b5915` with identical source, which contains AW-06 as merged in #445), installed RBZ built from
that head (SHA-256 `ad70209a6f95…`), SketchUp 26.1.188, Ruby 3.2.2, macOS. Fresh process on a fresh copy of the blank
template; synthetic data only.

Control: an MCP client outside SketchUp over HTTP to the real loopback listener; native Edit > Undo and Redo through
the SketchUp menu bar. Development eval only for labelled setup: the token, a synthetic file library (one valid row,
350 rejected rows, a 30 KB note) and the approved export destination. Raw output is in the gitignored run folder.

| Assertion | Result |
| --- | --- |
| catalog-warnings-paged | The load answers compactly (generation 1, 352 warnings); the warnings page over 3 pages, 352 of 352 |
| large-note-rejoined | The 30,000-character note (45,102 bytes) rejoins exactly from detail fragments |
| stale-generation-refused | After a reload the old generation is `library.catalog_stale` |
| copy-and-assign-one-invoke | The Frame copy and its Window Type side assignment, built from the `describe` example, commit in one invoke and read back |
| native-undo-redo | One native Undo removes both the copied Frame and the assignment; Redo restores both |
| compact-export-roundtrip | The compact export with paged omissions writes the approved file, which parses back with its SHA-256 and library id |
| replies-within-budget | 27 tool results, largest 16,893 bytes, all within 24,576 |

Limitations: one export omission on the host, not the 180 the offline case uses; Material, Glazing and Psi copies and
the outside example kind are offline only, as are hosted v2 catalogs (the synthetic hosted provider writes its
credential to the OS store on a real host). Windows and SketchUp 2023 were not exercised.
