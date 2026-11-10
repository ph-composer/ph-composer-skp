# AW04 definition detail reads, 2026-11-10

Case `AW04` (agent-workflows stage AW-04, acceptance A07a of
[the packet](../../features/unscheduled/agent-workflows-2026-11/ACCEPTANCE.md)). Run on branch
`feat/agent-workflows-aw-07` at `0d5cd927` (PR #446, squash-merged to main as `009b5915` with identical source, which contains AW-04 as merged in #443), installed RBZ built from
that head (SHA-256 `ad70209a6f95…`), SketchUp 26.1.188, Ruby 3.2.2, macOS. Fresh process on a fresh copy of the blank
template; synthetic data only.

Control: an MCP client outside SketchUp over HTTP to the real loopback listener with a read and model_write token. It
creates every record through `invoke`. Development eval only for the labelled token issue and revoke. Raw step output
is in the gitignored run folder.

| Assertion | Result |
| --- | --- |
| metadata-30kb-exact | The whole list row is refused as too large; the summary names 1,503 keys; fragments rejoin the 1,500-key `user_data` and the 30 KB non-ASCII value exactly; `null` and `false` read back, an absent key is `target.not_found` |
| window-type-10x10 | Every element of a 10 x 10 Type pages back equal, with thermal values and install Edges; the Frame's 400 uses page |
| assembly-layers-and-uses | 30 Layers and every Layer-Segment page back equal; 400 Material uses page |
| compound-preview-by-part | The oversized delete-with-replacement preview answers compact with its digest; value, affected (401 rows, 34,487 bytes) and findings rejoin by part; the fresh digest applies and the replacement holds all 400 uses |
| stale-cursor-refused | A part cursor from before an interleaved edit is `query.cursor_expired` |
| reads-no-side-effects | No read changed the revision; selection, edit path and panel unchanged |
| replies-within-budget | 882 tool results, largest 16,817 bytes, all within 24,576 |

Limitations: the client's first attempt stopped on a driver bug before any write and was rerun in the same process.
The applied delete's result was over the reply limit and came back as a receipt; the reassignment was read back
through the replacement's uses. The unavailable-extension status is covered offline (`definition_detail_test`).
Windows and SketchUp 2023 were not exercised.
