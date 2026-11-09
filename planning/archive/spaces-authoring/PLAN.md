# Spaces: delivery plan

DATE: 2026-11-09
STATUS: Complete. Delivered in #410 to #415.
AUTHOR: Ed May, BLDGTYP; Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/352

The behaviour contract is [PRD.md](PRD.md); this plan is the order of work. Stage ledger in [STATUS.md](STATUS.md).

## How each stage runs

One stage, one branch, one PR, through the `pr-loop` protocol, with a real-host check on the head that merges.
Reviewer `gpt-6.1-sol`, except S10-1, which is a change of membership and export keying: `gpt-6-astra`.

## Stages

| Stage | Scope | Depends on | Host check |
| --- | --- | --- | --- |
| S10-1 | Membership by reference: the Zone reference on the Space record, scan, findings, export keying, Move to Zone as a record edit, Zone deletion offers to unhost (W6-9), the collection-copy contract (W6-10), stamp removal, contract and context updates | none | Host: Space hosted in a Zone and moved to another, Zone delete, a copied storey Group |
| S10-2 | Create Space outside a Zone: the review's preselected Zone picker (W6-3), placement outside when run inside an open Zone (W6-2), Space Groups Untagged (W6-4), wording, closed solids still refused (W6-7) | S10-1 | Host: draw at the root, draw in an open Zone; Zone Faces untouched |
| S10-3 | Show Spaces overlay and the W-046 label defect | S10-1 | Host: prism and label, with and without Colour by |
| S10-4 | Set height tool and Edit outline | S10-1 | Host: one Undo step each |
| S10-5 | Remove Space, keeping floors (W6-8) | none | Host: one Undo step |
| S10-6 | `space.floor_overlap`, a warning that does not block export (W6-11) | none | Offline; a host read of the finding |

## Consequences of the decisions

- **W6-4, Untagged:** #352's row "shown or hidden by tag" is met by the tag a user applies; nothing creates a Spaces tag.
- **W6-7, solids refused:** no solid conversion stage; the review states the outline-plus-height rule.
- **W6-11, warn only:** a double-counted overlap can reach the energy model, reported, not blocked.

S10-1 carries the risk: it replaces parent-based membership and the Zone stamp across the scan, export and copy paths. It lands first, alone.
