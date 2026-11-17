# P4c-03: The settings file and climate data folders

DATE: 2026-11-17
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4c-01 and owed check 1. Owns PH-Composer's per-computer settings file and Climate's
section of it: the list of climate data folders and the last dataset used, with the setup
commands that change them and the Setup view's summary line. Panel closed. Reading station files is
P4c-04; the dialog is P4c-08.

Behavior: [PRD](../PRD.md), "How it works" and "Climate data on this computer". Names:
[CONTRACTS](../CONTRACTS.md) section 5. Answers: W5, J1, J6; D4c-05, D4c-10; E3 in
[DECISIONS](../DECISIONS.md). Boards: none built here; boards 3 and 14 show what the commands
change. Paths are relative to `src/ph_composer/`.

This stage takes the stronger review lane: it adds a store outside the Model and outside
SketchUp's preferences.

## Entry checks

**Owed check 1.** Run on the host before any code, and record under `evidence/`:

1. Write a value with `Sketchup.write_default` in one installed SketchUp version and read it in
   a second. Record whether preferences are per version. If they are shared, the separate file
   still stands on J1's other reason, and the evidence says so.
2. On macOS, confirm the user's application-support folder as Ruby sees it inside SketchUp, that
   a `PH-Composer` folder there is writable, and that it is the same folder from both versions.
3. The Windows location, `%APPDATA%`, is written from Ruby's documented environment variable and
   marked unverified; no Windows host is in this plan (E3).
4. Fold the facts into `context/SKETCHUP_HOST_BEHAVIOR.md`, "Saving, dialogs and the panel".

Also read `library/setup.rb`, `shell/preferences.rb` and `shell/native_approval.rb` for the
failure rules and the approval route this stage follows, and settle C4c-1 (the display location).

## Steps

1. **`shell/computer_settings.rb`.** A foundation service naming no feature: the folder rule
   (macOS and Windows, with an injectable directory for tests, as `agent_access/connections.rb`
   has), `read(section)`, and `write(section) { |values| ... }` that re-reads the file, changes
   one section, writes a sibling file and renames it into place. Shape and failure rules as
   CONTRACTS section 5. A size bound on the file, as `Library::Setup` has.
2. **Climate's section.** `features/climate/folders/store.rb`: rows `{ id, name, location }` and
   `last_dataset_id`, validated on read; a row whose folder is missing is kept and reads as not
   found.
3. **Setup commands**: `folders.add` and `folders.locate` with a `Declarations::Approval` of kind
   `open_folder`; `folders.rename`; `folders.remove`; `folders.remember_dataset`. Adding a folder
   already listed, or one inside or around a listed folder, refuses `climate.folder_overlaps`, so
   one station is never listed twice. Codes: `climate.settings_unreadable`,
   `climate.settings_unavailable`, `climate.folder_not_found`, `climate.folder_overlaps`.
4. **`folders.list`** (query), in this stage without counts: id, name, the display location and
   found or not found. P4c-04 adds format, stations, states and files not read.
5. **Setup summary.** A function answering the one-line summary ("No climate data folder", "1
   folder"); P4c-04 adds the station count. The Setup view entry itself is registered in P4c-08,
   when its button has a dialog to open, so no dead button ships.
6. **Privacy.** A test that no declared param, result field or diagnostic log line of these
   operations holds an absolute path.
7. **Contract and docs.** API minor bump, `make fixtures`; `context/TECH_STACK.md` gains the
   settings file beside "Display units"; `context/CONTRACTS.md` gains its shape; the agent guide
   says which commands need the `setup` capability; `context/UBIQUITOUS_LANGUAGE.md` drops
   "planned" from Climate data folder.

## Source

| File | Disposition |
| --- | --- |
| `library/setup.rb`, `library/setup_commands.rb` | Pattern for a per-computer store's states and for approved add commands. Not reused as the store |
| `shell/native_approval.rb`, `shell/declarations.rb` (`Approval`) | The folder chooser |
| `agent_access/install.rb` (`setup_summary`) | Pattern for a summary line |
| `core/diagnostics.rb` (`data_root`), `agent_access/connections.rb` | Precedents for a per-user folder; the new rule sits in `shell/computer_settings.rb` |

## Tests (write first)

1. The file is created on first write; a second section written later keeps the first.
2. Two writers on different sections lose neither; an interrupted write leaves the old file.
3. An unreadable file, and one from a later schema version, are left as stored; reads report
   and writes refuse.
4. Add, rename, locate and remove change the section; a scripted add with no approval refuses.
5. A missing folder keeps its row and reads not found; locate repairs it; nothing removes it.
6. Overlapping folders refuse.
7. No absolute path in params, results or logs.
8. The summary reads each state: no folder, one, several, and an unreadable settings file.

## Host gate

CM03 in [ACCEPTANCE](../ACCEPTANCE.md).

## Leaves for the next stage

P4c-04 reads the folders this stage lists. P4c-08 builds the dialog and registers the Setup entry.

## Done when

CM03 passes, owed check 1 is recorded and folded into `context/`, and C4c-1 is answered.
