# P4c-04: The Phius station reader, the station list and attach

DATE: 2026-11-17
STATUS: Implemented on branch `feature/climate-p4c-04`, 2026-11-18. Ed authorized every stage on 2026-11-17. Departures below.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4c-02, P4c-03 and owed check 3. Owns the one built-in reader of Phius station files,
the folder counts, the station list with its distance and verdict, the action that attaches,
replaces and updates a station, and the source status of an attached one. Panel closed. The
dialog and the picker that show these are P4c-08 and P4c-09.

Behavior: [PRD](../PRD.md), "What a Phius station file holds", "Choosing a station" and "An
attached climate". Names: [CONTRACTS](../CONTRACTS.md) section 6. Answers: W5, W6, W8, J1, J3,
J6, J7, R3, R8; D4c-06, D4c-11. Boards: none built here; boards 3, 4, 6, 11, 16 and 17 show the
data these reads return. Paths are relative to `src/ph_composer/`.

## Licensed data

No station file, name, coordinate or value from a licensed dataset enters the repository, a
fixture, a test name, a commit message, a document or a capture. Public fixtures are invented
files of the same shape. The private corpus is read only by tests that take its location from
`PH_COMPOSER_CLIMATE_CORPUS` and skip when it is unset; its location is recorded only in the
gitignored `_private/climate/MANIFEST.md`. This stage writes the first such test, so it sets the
pattern (Minitest `skip` with a message naming the variable).

## Entry checks

**Owed check 3.** Before the read is designed, measure and record under `evidence/` (timings and
counts only):

1. In SketchUp's Ruby, the time to walk a real-size folder and parse every station header, cold
   and warm. The Python figure was 0.15 s for 1,007 files (PRD).
2. The same for a cloud-synced folder whose files are not downloaded: whether a read blocks,
   downloads, or fails, and how long the main thread is held.
3. Apply D4c-11: under 0.5 s the read is synchronous; over, it is sliced with `DeferredWork`;
   a cache only if a warm read exceeds 2 s. Record which applies and why.

Also at entry:

4. C4c-6: `Digest::SHA256` loads in SketchUp's Ruby on the current host.
5. C4c-2: the matching name of a station, the file name's stem or the header's name.
6. Fix the reader's exact row labels, column order and number formats from PH-Navigator's
   importer and the structure notes in the PRD, checked against the private corpus for
   structure only (decimal separators, blank cells, trailing columns). Record structure, never
   content.

## Steps

1. **Synthetic fixtures** under `tests/fixtures/climate/`, as ACCEPTANCE lists, written by a
   small generator in `tests/support/` so their values are plainly invented.
2. **The reader.** `features/climate/stations/phius_station_file.rb`, pure: bytes to a parsed
   station (header, eight series of twelve months and three design values, January and July wind
   speeds) or a typed failure naming the row. Windows-1252 in, UTF-8 out. The checksum is
   SHA-256 of the bytes.
3. **The folder walk.** `features/climate/stations/folder_scan.rb`: every file under a folder,
   subfolders included; a station is a `-mon.txt` file that parses; its state is its folder's
   name and its key the folder name and file name; everything else is counted by kind. Sliced or
   not per the entry check. The walk reads headers for the list and a whole file only on attach.
4. **`folders.list`** gains format, station count, state count and files not read by kind; the
   Setup summary gains the station count.
5. **`stations.list`** (query): one folder's stations with key, name, state, latitude, longitude
   and elevation, each with distance, elevation difference and verdict from P4c-02's limit check
   against the Model's site. Refuses `climate.site_not_set` when there is no site (J3) and
   `climate.folder_not_found`.
6. **`climate.attach_station`** (action): folder id and station key in; Ruby reads the file,
   calls `Record.from_station` with the folder's dataset name, and creates or replaces the
   climate in one Undo step. Undo names "Attach Climate Station" and "Replace Climate Station".
   Refuses with no site, a missing folder or file, or a file that does not parse
   (`climate.station_unreadable`). The result names what was replaced and how many edited cells
   were lost, for the picker's notice.
7. **`climate.source_status`** (query): looks for the attached station's name and state in
   every folder, then compares checksums: found, changed, or not on this computer; the matching
   folder's id and station key when found or changed, so Update from File can call
   `attach_station`.
8. **Agent access.** These reads touch the user's disk. Confirm with the architecture review
   that the `read` capability is right for a list that returns locations and elevations only,
   and record the answer in `context/AGENT_INTERFACE.md`.
9. **Contract and docs.** API minor bump, `make fixtures`; the agent guide recipe: list folders,
   list stations, attach the nearest passing one; the walkthrough is extended;
   `context/CONTRACTS.md` gains the reader's rules.

## Source

| File | Disposition |
| --- | --- |
| `library/file_provider.rb` (bounded binary read), `library/library_file.rb` | Pattern for reading a user's file without trusting it |
| `session/deferred_work.rb`, `library/connection/load.rb` | Pattern for a sliced read polled on the main thread, used only if the entry check asks |
| `features/climate/climate/` from P4c-02 | `Record.from_station`, the limit check |
| `features/climate/folders/store.rb` from P4c-03 | The folders |

## Tests (write first)

1. The reader parses a well-formed synthetic file to exact values; a missing series row, a short
   row and a non-number each fail with the row named; a Windows-1252 name reads correctly.
2. The walk counts stations, states and files not read by kind; `-mon2.txt` and a malformed
   `-mon.txt` are not stations; a station in a nested subfolder takes its own folder as state.
3. `stations.list` gives hand-checked distances and verdicts on both sides of each limit, and
   refuses with no site.
4. `attach_station` writes the record, the as-read copy, the source and the wind-speed mean in
   one Undo step; over an existing climate it is one Undo step and reports lost edits; no value
   of the file appears in the action's params.
5. Source status: found; changed after the fixture file is rewritten; not on this computer after
   the folder is removed; found again in a second folder with a different name (J6).
6. Attach then export nothing: no path is in the record (the schema already refuses one).
7. A private-corpus test, skipped when the variable is unset: every `-mon.txt` in the corpus
   parses or is reported, and the counts are plausible. It asserts counts and timings only.

## Host gate

CM04 in [ACCEPTANCE](../ACCEPTANCE.md).

## Leaves for the next stage

P4c-08 shows the counts; P4c-09 shows the list and calls attach; P4c-10 shows source status.

## Done when

CM04 passes, owed check 3 is recorded, and C4c-2 and C4c-6 are answered.

## Departures, 2026-11-18

- **Entry checks** ([evidence](../evidence/owed-check-3-20261118.md)): the read takes 0.06 to 0.08 s
  for 1,007 files in SketchUp's Ruby, so it is synchronous and the plan's split rule does not apply;
  the walk is bounded instead (D4c-21). The cloud-synced case was not run: it would need a change
  to Ed's Dropbox sync settings. C4c-2 and C4c-6 are settled (D4c-18).
- **Two actions** (D4c-19): an action has one Undo name, so step 6's "Attach Climate Station" and
  "Replace Climate Station" are `climate.attach_station` and `climate.replace_station`. Both are
  guarded by the request's revision; neither takes the climate's values.
- **Paging and keys** (D4c-20): `stations.list` pages nearest first; a key is the file's path inside
  the climate data folder.
- **`Record.from_station`** takes the stem as `station_name` in its source (D4c-18), a change to
  P4c-02's builder.
- **Fixtures** are committed under `tests/fixtures/climate/`, written by
  `tests/support/climate_station_files.rb` through `make fixtures`, with `-text` in `.gitattributes`
  so their CRLF and Windows-1252 bytes survive.
- **The list is read from headers** (CONTRACTS section 6 and step 3): a `-mon.txt` whose header reads
  and whose series rows do not is listed and counted as a station, and attach refuses it with
  `climate.station_unreadable` naming the row. A file whose header does not read is not a station.
  A full parse of every file in the walk measured 0.25 s offline, so this can change if the dialog
  needs exact counts.
- P4c-09 calls `replace_station` for Replace, and P4c-10 for Update from File.
