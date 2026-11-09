# Spaces: stage ledger

DATE: 2026-11-09
STATUS: Planned; implementation waits for Ed's go.
AUTHOR: Ed May, BLDGTYP; Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/352

Plan: [PLAN.md](PLAN.md). States: `Scoped` · `In progress` · `Implemented on branch` · `Merged to main` · `Blocked` · `Deferred`.

| Stage | State | PR | Evidence |
| --- | --- | --- | --- |
| S10-1 | Merged to main | [#410](https://github.com/ph-composer/ph-composer-skp/pull/410) | Offline gate and host check are recorded on the PR. W6-9 is the `space.zone_missing` finding with the `unhost` repair: Zones have no delete action, a Zone is erased natively |
| S10-2 | Merged to main | [#411](https://github.com/ph-composer/ph-composer-skp/pull/411) | Offline gate and host check are recorded on the PR. No Space nests: `test_no_route_leaves_a_space_inside_a_zone`. Nested Spaces and the Zone stamp on Groups are gone; `stamp_container` is removed |
| S10-3 | Merged to main | [#412](https://github.com/ph-composer/ph-composer-skp/pull/412) | The W-046 defect is readouts off by default: Show Spaces (`ph_composer.spaces.show`, Zones > Spaces Table options) starts on in every Model session and draws each Volume's prism outline and each Space's label with or without a mode. Offline gate and host check are recorded on the PR |
| S10-4 | Merged to main | [#413](https://github.com/ph-composer/ph-composer-skp/pull/413) | Set height: `features/spaces/set_height_tool.rb` picks a Volume's prism by pointer ray (`PrismPick`, every visible Volume's prism read once per revision), a drag or a typed value is one `update`. Edit outline: `edit_outline_menu.rb`, unprotect then `context.open`, as the panel's Enter. A Space with several Volumes refuses and says to select one. Offline gate and host check are recorded on the PR |
| S10-5 | Implemented on branch | | Remove Space: `ph_composer.spaces.remove`, `RemoveSpaceStep`, beside Delete Space. Every Spaces record at or below the Space goes, the Space and Volume Groups explode innermost first, the Faces stay at their positions as plain geometry, one Undo step. A record below the Space in shared storage or copied elsewhere refuses. Offline gate and host check are recorded on the PR |
| S10-6 | Scoped | | |
