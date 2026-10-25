# GitHub organization and SketchUp repository migration

DATE: 2026-10-25
STATUS: Implemented and native-verified; merge delivery tracked in PR #306.
ISSUE: [#305](https://github.com/ph-composer/ph-composer-skp/issues/305)

## Recommendation and scope

Ed created the `ph-composer` GitHub organization on 2026-10-25. Transfer the existing repositories:

| Current | Proposed |
| --- | --- |
| `bldgtyp/ph-composer` | `ph-composer/ph-composer-skp` |
| `bldgtyp/ph-composer-library-provider-example` | `ph-composer/ph-composer-library-provider-example` |

Ed confirmed the required local layout on 2026-10-25:

```text
~/Dropbox/bldgtyp-00/00_PH_Tools/ph-composer/
  ph-composer-skp/
  ph-composer-library-provider-example/
```

The outer folder is an organization container, not a Git repository. Move both existing
checkouts intact, including their Git metadata and ignored/private files. Rename the current
main checkout from `ph-composer` to `ph-composer-skp`; retain the example checkout's basename.

This is repository organization, not a product, persistence or public API rename. Keep the
PH-Composer product name, `PhComposer` Ruby namespace, `ph_composer` prefixes, extension loader
and installed directory, dictionary keys, feature/provider identifiers, translation package,
MCP configuration names, preferences and existing RBZ naming. Keep BLDGTYP copyright and DCO
attribution. Moving repository ownership does not change licensing or copyright ownership.

Use `ph-composer` as the project family and `ph-composer-skp` as its SketchUp implementation.
The suffix is reasonable given the proposed naming; `sketchup` would be more explicit to a new
reader, but does not warrant blocking the requested `skp` choice. The repository description
and README should spell out SketchUp. Preserve the example repository name as requested:
its README must continue to explain that it currently implements the SketchUp Ruby contract.
Organization placement does not make that contract host independent.

Future Blender, Revit or Rhino implementations can have separate repositories. Do not extract
a common core, add new packaging or create speculative host repositories during this migration.
The current four-layer architecture and HBJSON boundary remain intact. Any future shared
component should be extracted against actual consumers and its own scope and acceptance plan.

## Evidence and known impact

Inspection on 2026-10-25: local `main` was clean, with origin
`https://github.com/bldgtyp/ph-composer.git`. Connected GitHub metadata reports both repositories
public, on `main`, with repository admin access. This does not establish target-organization
ownership, source-organization transfer permission or applicable organization policies.

Tracked-file search found `bldgtyp/ph-composer` in 281 files (759 occurrences), of which 271
files are in `planning/`. These are inventory figures, not a replacement specification.
The provider name appears in two planning files. Refresh this inventory at implementation.

Active address-bearing surfaces include:

- `src/ph_composer/shell/support_dialog.rb`: Help and issue-report URLs, including commit-specific Help links.
- `src/ph_composer/shell/api.rb`: discovery's refusal-documentation URL.
- `src/ph_composer/help/index.html`: release links in shipped Help.
- `tests/support_dialog_test.rb` and `tests/api_reference_test.rb`: URL expectations.
- `README.md`, `SECURITY.md`, `docs/HELP.md`, `docs/API_REFERENCE.md`, and
  `.github/ISSUE_TEMPLATE/config.yml`: public navigation and reporting routes.
- `planning/.instructions.md`, `planning/DECISIONS.md` D8 and the founding brief:
  current repository-home statements, preserving their dated history.
- Provider example `README.md`: link to the main repository. Its `bldgtyp_example_library`
  files and `bldgtyp.example_library` IDs are not repository addresses and should remain stable.

The inspected `.github/workflows/ci.yml` uses third-party actions and checkout of its own
repository; it has no hardcoded old owner/repository. This does not verify GitHub-side settings
or external consumers. Local examples contain absolute-path placeholders with `ph-composer`;
some development tools derive the repository root from their own file location.

GitHub's [transfer documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/transferring-a-repository)
states that transfers preserve Git history, issues, PRs, releases and repository-associated
webhooks, secrets and deploy keys, with redirects for old repository and Git URLs. Target
organization defaults apply; source organization team access must be mapped explicitly.
Packages have registry-dependent behavior. GitHub Pages is not redirected.

GitHub's [rename documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository)
warns that hosted action calls do not redirect and that reusing the old repository name breaks
redirects. Actions and reusable-workflow consumers need explicit address updates. Neither
redirects nor retained repository secrets prove that an external integration remains authorized.

## Execution sequence after authorization

1. **Preflight and capture.** Verify the exact organization handle through GitHub creation;
   an unauthenticated profile fetch returned 404, which does not establish availability or
   reserve it. Confirm source transfer permission and target owner access. Inventory both
   repositories' IDs, default branches, refs/tags, open PRs/issues, releases/assets, rulesets,
   protection/check names, collaborators/teams, Actions policies, secrets names (never values),
   environments, webhooks/apps, deploy keys, Pages/domains, packages, LFS and security settings.
   Record absence explicitly. Resolve active delivery or temporarily pause merges during cutover.
2. **Prepare reviewable changes.** Make a bounded migration branch and patches for both
   repositories. Update canonical addresses and current documentation. Review every matching
   category, including hidden configuration and ignored local tooling where applicable.
   Preserve historical prose and append-only native evidence; record redirects in this plan
   rather than rewriting old result records. Active ledgers may receive canonical links.
   Update D8's current-home decision at cutover with a dated entry, without erasing its history.
3. **Create organization.** Confirm plan, billing contact and maintainers with Ed. Recommend
   Ed and John as owners for continuity, subject to their intended roles; invitations require
   authorization. Set intentional base permissions, 2FA policy and Actions access, and map
   current collaborators to the required roles. A new organization does not inherit all of
   BLDGTYP's organization-level configuration or identity. Do not initialize destination repos.
4. **Transfer.** Transfer the main repository and use GitHub's transfer-time rename to
   `ph-composer-skp` while acting as target owner. Transfer the provider example unchanged.
   Transfer existing repositories rather than copying or recreating them. Verify the same
   repository IDs and retained refs, issue/PR numbers and release assets. Keep visibility public.
5. **Restore operational access.** Compare captured settings with target behavior; restore
   protections and required checks before normal merges resume. Reauthorize installed GitHub
   Apps, repository-scoped tokens and connected tools as necessary. Check inherited secrets,
   rulesets, team permissions, external CI, security reporting, any OIDC subject restrictions,
   packages and Pages only where present. Recheck pending PR/check behavior after the move.
6. **Land changes and update clones.** Merge signed migration commits through required checks.
   Point both origins explicitly at their canonical URLs. Complete the confirmed local layout
   as a coordinated final cutover. Inspect machine-workflow guidance first, stop active
   host/preview processes and inventory worktrees, symlinks and absolute references. Because
   the desired parent path is occupied by the current checkout, first rename that checkout
   to an available temporary sibling, create the empty `ph-composer/` container, then move
   the checkout into it as `ph-composer-skp/` and move the example alongside it. Never create
   the container inside the existing checkout or overwrite an occupied destination. Preserve
   ignored/private files and Git metadata; repair linked-worktree registrations where needed.
   Repair workspace registrations, installed dev loaders/symlinks, environment entrypoints,
   editor/project settings, skills and automation paths. Avoid two installed extension copies.
   Audit repository-relative references as well: the example remains a sibling of the main
   checkout, but `ph-navigator-sketchup` and other existing tool repositories become one level
   farther away. Update active predecessor links and scripts accordingly, while preserving
   historical evidence. Record old and new absolute roots so external path repairs are explicit.
7. **Verify and hand off.** Complete the acceptance list below, record the final addresses,
   settings differences and remaining limitations here, and update the planning index. Leave
   the original names unused to preserve redirects. Update external references under their
   own authorization; capture any inaccessible consumers as follow-ups.

## Acceptance and recovery

- Both canonical repositories resolve; IDs, commit SHAs, tags, issue/PR numbers, releases
  and contributor history match preflight. Check old repository, issue, PR and Git redirects.
- Maintainers can administer and push; intended users can read and contribute; protections,
  required checks, security reporting and integration access work under the target settings.
- Run focused URL/API-reference/support-dialog/provider tests, refresh the vendor manifest
  for changed shipped assets as required, then `make ci` and the existing RBZ verification.
  Confirm remote CI passes in both repositories where configured.
- In a fresh current SketchUp process, verify the same extension identity loads once, opens
  an existing synthetic model with its authored data intact, reaches Help and issue routes,
  and exports HBJSON. Run the provider example's panel-closed copy/reuse/read-back walkthrough
  and Undo check. Use established host tooling and retain evidence; this does not close the
  separate SketchUp 2023, Windows or public-release gates.
- Search tracked current surfaces for obsolete canonical URLs; classify remaining matches
  as historical evidence, stable identifiers or unresolved work. Check any renamed local
  checkout from its new path, including build/install and fresh host startup.
- Do not alter historical binaries or acceptance fingerprints to make their addresses current.
  Old builds may continue using redirects; a later build contains corrected canonical links.

Before transfer, the migration branch is simply discardable. After transfer, prefer repairing
settings/links in place. Reverse transfer or rename is a separate operational action requiring
permissions and available names; retired namespaces and redirect behavior can prevent an exact
return. A Git backup preserves refs, not the complete GitHub service state. Keep the preflight
settings record and do not promise atomic rollback of both repositories and integrations.

## Effort and remaining decisions

Estimate: moderate operational coordination, low code complexity. Allow roughly half a day
to one day for preflight, two transfers, bounded patches and verification if permissions are
ready and no external publishing integrations are found. Organization setup or app approvals
can add elapsed time. The required local moves increase machine-specific work; changing runtime
identities would be a separate, much larger compatibility project and is not recommended here.

The organization handle, Free plan and Ed's owner access are verified. Ed confirmed the local
layout and authorized restoring John's previous read access; both invitations were sent.
Ed updated the sidebar project folder; the project listing confirms the new checkout path.
The trusted-project configuration is repaired.

## Execution receipt, 2026-10-25

- Both transfers completed. Repository IDs remain `1376194878` (SketchUp) and `1399931972`
  (provider example), with the same pre-transfer `main` commits and four open SketchUp issues.
  Neither repository had associated GitHub Packages, tags, releases, forks, Pages, webhooks, deploy keys, environments or
  repository secrets. Existing source PR lists were empty. Old Git URLs resolve to the same HEAD.
- Main's two required checks and branch protection survived unchanged. The example remains
  unprotected as before. Actions permissions are unchanged. Secret scanning became disabled
  during transfer and was explicitly restored on both repositories. Other captured security
  flags remain unchanged. The target reports no installed GitHub Apps; the connected GitHub
  tool successfully reads the new repository. No claim is made about unenumerated external consumers.
- Both complete local directories moved into the confirmed organization container. Origins,
  Python environment entrypoints, Codex's trusted-project entry and the global native-acceptance
  skill symlink now use the new roots. There were no linked worktrees. Internal skill symlinks
  and installed SketchUp extension filenames remain intact. Active predecessor references
  and example load paths were repaired. No retained native evidence was rewritten.
- Canonical URL changes cover shipped Help, Help/issue reporting, API discovery, generated API
  reference, contributor/security navigation and active planning links. Historical archive URLs
  and runtime/cache/provider identifiers deliberately remain stable. The API reference was
  regenerated and committed separately because `fixtures-check` requires generated outputs
  committed before its final clean-state check; the generated delta was exactly the intended URL.
- `make ci` passed on Ruby 3.2.2: 2,117 Ruby tests / 23,700 assertions, 737 JavaScript tests,
  246 Python tests, lint/type/runtime/hostkit/fixture/help checks and RBZ verification.
  The RBZ has 490 files and fits the existing installed-size gate. No runtime-manifest update
  was required: shipped edits are Ruby and Help, outside the pinned `html/` and `python/` assets.
- One bounded independent review found a stale roadmap D8 statement and missed active
  predecessor paths. Both were corrected. Its follow-up review of the provider API repair
  found no remaining correctness issues. Runtime and persistence identities are unchanged.
- The actual standalone provider walkthrough initially reproduced `request.unknown_operation`
  for library loading through the old view entrypoint, then `params.invalid` for retired
  `choice: inspect`. This pre-existing incompatibility blocked the planned acceptance check.
  The minimal repair uses the setup grant/entrypoint and the `in_file` resolution query.
  Offline execution against the actual sibling repository passed copy and unchanged reuse.
  Provider changes merged through [PR #1](https://github.com/ph-composer/ph-composer-library-provider-example/pull/1)
  (canonical link) and [PR #2](https://github.com/ph-composer/ph-composer-library-provider-example/pull/2)
  (walkthrough compatibility).
- Native acceptance used SketchUp 26.1.188 / Ruby 3.2.2, build `efcc99f1b3f3`, source
  `766aabc85220`, with one registered/loaded `ph_composer` extension. The unchanged synthetic
  source Model SHA-256 is `84b505124b4506384e65a7ef2a32c190605b0d0d8159e7b2bdc72bd043cbc007`;
  the installed RBZ SHA-256 is `0449b0c6b84712b1688a1a28beecad2d9e7b9dfd524529521f9dd320e375cfe0`.
- In a fresh process, the panel-closed external provider copied a Material, reused the same ID
  without writing, and native Undo/Redo removed/restored that ID in separate observed calls.
  HBJSON export completed through the normal runtime and reloaded in Honeybee as two Rooms.
  The pre-existing synthetic fixture's defaulted thermal-mass/unavailable-definition findings
  remained nonblocking; this is export-path acceptance, not a clean-model or certification claim.
- Save and fresh-process reopen preserved exact selected authored IDs, values and references
  for 2 Zones, 12 Faces, 7 Materials, 5 Assemblies and 4 Spaces. The normal reopened process
  has no example provider injected. Native pixels confirmed the populated Zones panel and
  Help & Diagnostics; Help exists and its commit-specific URL and issue URL use the new address.
  The session's diagnostic warning/error read contained no records.
- Private settings snapshots, driver snippets, identity and observation JSON, export artifacts,
  diagnostic/wait results and full local gate logs are retained in `_private/github-migration/`.
  They remain untracked. Current-host acceptance does not close SketchUp 2023, Windows or release gates.

Delivery is tracked in [PR #306](https://github.com/ph-composer/ph-composer-skp/pull/306).
The remaining human follow-up is John accepting the read-access invitations. The Codex sidebar
project path is verified correct. Neither changes the verified runtime or repository contents.
