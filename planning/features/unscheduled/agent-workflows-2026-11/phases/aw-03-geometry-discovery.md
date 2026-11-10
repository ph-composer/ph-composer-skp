# AW-03 · Find existing geometry without selection

STATUS: Implemented on branch `feat/agent-workflows-aw-03` (API 1.36); review and host/MCP gate in STATUS. ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/439 (implementation); #435 tracked the review/planning publication.
DEPENDS ON: AW-01/AW-02. FINDING: R06. CONTRACT: C04. ACCEPTANCE: A06.

## Outcome

From empty selection, an agent can find candidates for a first Zone/Space and unassigned Thermal
Bridge Edges, then invoke the existing operations with complete, current references.

## Work

1. Implement a bounded child inventory for explicit root/container paths, with native kind, name,
   occurrence path and registered ownership. Reuse traversal/transform primitives and never recurse
   through the entire model by default. Declare visibility/locked/shared filtering semantics.
2. Add feature-owned candidate/detail reads using the existing Make Zone/Spaces eligibility functions.
   Include existing Space/Volume candidates in the same documented route without removing them.
3. Add explicit-path and candidate Edge reads that return the complete Thermal Bridge reference,
   stored assignment/expected values, endpoints and path-level refusal. Reading a schedule's member
   Edge must not require `runs.locate` or changing the user's selection.
4. Cover acquisition for existing Window convert/restore and selected-solid height workflows with
   owner-derived candidates where the source contains enough proof. Return an explicit need for user
   selection when proof is unavailable; do not guess a host or Type from a display name.

## Source and tests

Start at `shell/context_commands.rb`, core geometry/reference traversal, Zones containment/Make,
Spaces `create_faces`, eligibility and scoped reads, Windows convert/restore readers, Thermal
Bridges `assignment/selection` and `scan/occurrences`. Extend existing context, containment,
Spaces candidate, Window conversion and thermal assignment tests. Use the same functions the writes
use, with new tests for root/plain wrapper, rotation, nested/shared occurrences, unassigned identity,
locked/hidden/foreign-owned objects and revision-expired cursors. Reads must change no dictionaries,
selection, edit path or revision. Large loops hand off to bounded detail from AW-05.

## Native gate and done

Panel closed and selection empty: find a plain candidate Group and Make Zone; find drawn floor
Faces and create a Space; discover an unassigned Edge, assign it, reread by path, clear and reread.
Confirm transformed SI geometry and native Undo/Redo. External clients must not use developer eval
to obtain IDs. Native fixture creation is allowed before the client scenario and explicitly recorded.

No native drawing, transformation, save/open/close, arbitrary selection or generic eval API is in scope.
Complete PLAN gates and add the first-target recipes through docs-pass.
