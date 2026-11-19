# P4c-03: The settings file and climate data folders

DATE: 2026-11-17
STATUS: Complete. Merged to main 2026-11-18 (PR #514, `7c3312ea`). CM03 Pass on `45224965`, rechecked Pass on `1ca85729` in P4c-12's run. Authorized 2026-11-17 with every Climate stage ([STATUS](../STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

## Entry and scope

Requires P4c-01 and owed check 1. Owns PH-Composer's per-computer settings file and Climate's
section of it: the list of climate data folders and the last dataset used, with the setup
commands that change them and the Setup view's summary line. Panel closed. macOS only: the
Windows location is future work in the Windows support packet (E3). Reading station files is
P4c-04; the dialog is P4c-08.

Behavior: [PRD](../PRD.md), "How it works" and "Climate data on this computer". Names:
[CONTRACTS](../CONTRACTS.md) section 5. Answers: W5, J1, J6; D4c-05, D4c-10; E3 in
[DECISIONS](../DECISIONS.md). Boards: none built here; boards 3 and 14 show what the commands
change. Paths are relative to `src/ph_composer/`.

This stage takes the stronger review lane: it adds a store outside the Model and outside
SketchUp's preferences.

## Entry checks

**Owed check 1.** Run on the host before any code, and record under `evidence/`:

1. On macOS in SketchUp 2026, confirm the user's application-support folder as Ruby sees it
   inside SketchUp, that a `PH-Composer` folder there is writable, and that it sits outside
   SketchUp's versioned folder.
2. Record where `Sketchup.write_default` keeps its values on this host and whether that place is
   named for the SketchUp version. That is as far as one installed version can show.
3. Fold the facts into `context/SKETCHUP_HOST_BEHAVIOR.md`, "Saving, dialogs and the panel".

Not run in this packet (E3), and listed in [PLAN](../PLAN.md#deferred-out-of-this-packet):

- **Two SketchUp versions.** Ed tests on SketchUp 2026 only for now. Writing a preference in one
  version and reading it in another, and reading the same settings file from both, wait for a
  second supported version to be installed; the 2023 floor packet is where that first happens.
  The separate file does not wait on the answer: J1 gives a second reason for it, that the
  extension's folder is replaced on reinstall.
- **Windows.** No Windows location is chosen, written or tested here.

Also read `library/setup.rb`, `shell/preferences.rb` and `shell/native_approval.rb` for the
failure rules and the approval route this stage follows, and settle C4c-1 (the display location).

## Steps

1. **`shell/computer_settings.rb`.** A foundation service naming no feature: the folder rule
   (macOS only, with an injectable directory for tests, as `agent_access/connections.rb` has;
   on any other platform the service answers `climate.settings_unavailable`), `read(section)`, and `write(section) { |values| ... }` that re-reads the file, changes
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
9. On a platform other than macOS the service is unavailable and the folder commands refuse.

## Host gate

CM03 in [ACCEPTANCE](../ACCEPTANCE.md).

## Leaves for the next stage

P4c-04 reads the folders this stage lists. P4c-08 builds the dialog and registers the Setup entry.

## Departures, 2026-11-18

- **The service names no feature** (D4c-17). `shell/computer_settings.rb` raises
  `ComputerSettings::Refused` with a reason; Climate's store maps it to `climate.settings_unreadable`
  (unreadable, later version) or `climate.settings_unavailable` (not macOS, too large, could not be
  saved). Step 1 had the service answer the climate code itself.
- **A lock across the write** (D4c-17). Re-read and rename alone leave a window where one process's
  stale copy erases another's section; a write holds `settings.lock`, at most two seconds.
- **A later schema version is neither read nor written** (D4c-17), where CONTRACTS said read-only.
- **C4c-1** settled as D4c-16: the home and `/Volumes/` forms, and `…/` with the last two names
  elsewhere.
- `folders.list` answers `{ id, name, display_location, found }`; `remove` and `remember_dataset`
  answer the list. Removing the remembered folder clears `last_dataset_id`.
- Add and Locate refuse before the chooser opens when the settings cannot be read or are
  unavailable, and Locate when the id is unknown (each command's precondition).
- An approved `open_folder` location stands in for the chooser, as for the Library's folder add.

## Done when

CM03 passes, the macOS half of owed check 1 is recorded and folded into `context/`, and C4c-1 is
answered.
