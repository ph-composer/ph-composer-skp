# AW05 occurrence detail reads, 2026-11-10

Case `AW05` (agent-workflows stage AW-05, acceptance A07b of
[the packet](../../archive/agent-workflows-2026-11/ACCEPTANCE.md)). Run on branch
`feat/agent-workflows-aw-07` at `0d5cd927` (PR #446, squash-merged to main as `009b5915` with identical source, which contains AW-05 as merged in #444), installed RBZ built from
that head (SHA-256 `ad70209a6f95…`), SketchUp 26.1.188, Ruby 3.2.2, macOS. Fresh process on a fresh copy of the blank
template; synthetic data only.

Control: an MCP client outside SketchUp over HTTP to the real loopback listener with a read, view and model_write
token. Development eval only for labelled setup: the token, native geometry (a wrapper turned 30 degrees and moved
10 m holding a Zone Group with a 20 x 8 m wall with 450 holes, a floor and a 300-Edge polyline; 60 loose root Edges),
and 60 assignments on the loose Edges written to the record store, a stranded state the product refuses to author.
The oracle is the in-process whole reads and `Sketchup::InstancePath` world points. Raw output is in the gitignored
run folder.

| Assertion | Result |
| --- | --- |
| unit-metadata-30kb | The whole row is refused as too large; the summary and fragments rejoin 30 KB of `user_data` exactly; every part equals the whole read |
| host-450-holes | Summary 4 outline points, 450 holes, 2 Units; 450 of 450 holes paged |
| zone-findings-and-restore | Blocked: the fixture has no legacy stamps or component Zones (0 restore offers, 0 findings); offline only |
| run-members-world | 300 members paged equal to the whole schedule; all 300 end points match InstancePath world coordinates; 60 orphan findings paged |
| areas-and-floor-loops | Areas and Assembly usage page equal to the whole reads; Floor Segment loops blocked: the fixture has no Space; offline only |
| guarded-metadata-update | Reconstructed metadata guards an update that reads back exactly; after a later edit the write refuses `target.changed` with both Units unchanged |
| pages-equal-whole-reads | Every reconstructed table equals the whole in-process read; no read changed the revision |
| replies-within-budget | 103 tool results, largest 24,091 bytes, all within 24,576 |

Limitations: three earlier attempts stopped on driver bugs and were each restarted on a fresh fixture in a fresh
process; their output is kept privately. The run is 300 Edges, not the 799 the offline case uses. The convert review
of 196 rectangles is offline only. Windows and SketchUp 2023 were not exercised.
