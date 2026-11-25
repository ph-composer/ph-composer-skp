# Brand and public documentation: plan

DATE: 2026-11-25
STATUS: Scoped. Stages BR-01 to BR-09 drafted; none authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

The brand is decided in [DECISIONS.md](DECISIONS.md). This plan turns it into assets, an in-app
change, a site and a documentation suite. Each stage needs Ed's go before work starts.

## What the December soft beta needs

A beta tester has to find the project, install it, build one model and know where to report a
problem. That sets the minimum:

| Needed for the beta | Stage |
| --- | --- |
| The mark as files, at every size it is used | BR-01 |
| A toolbar button and extension icon in SketchUp | BR-02 |
| A landing page with an install link | BR-05 |
| An install guide, one first-model tutorial, troubleshooting and a "how to report" page | BR-06 |
| A link from the PH-Tools sites | BR-08 |

The panel recolour (BR-03), the Design System update (BR-04), the full documentation suite
(BR-07) and the video (BR-09) can follow the beta. Testers can use the panel in its present
colours.

## Stages

### BR-01. Asset kit

Turn the mark generator into the source of record and export the files every other stage uses.

- Move [mockups/generator/lift_mark.py](mockups/generator/lift_mark.py) to its permanent home
  (BR-O5) and add a product-colour argument.
- Export SVG for every variant, and PNG at 16, 24, 32, 64, 128, 256 and 512 px. The 16 and 24 px
  files use the plain variant and are checked pixel by pixel, not just scaled.
- Export a favicon set and a social-preview image.
- Set the wordmark lockups in Figtree: suite, and one per product.
- Write a one-page usage note: clear space, minimum size, the colour table, what not to do.

Needs first: BR-O1 (product colours), BR-O4 (white on white), BR-O5 (home).
Done when: the files exist in the chosen home and a page shows each at its real size.

### BR-02. Icons in SketchUp

The extension has no toolbar today; its commands are menu items only
(`src/ph_composer/shell/commands.rb`). This stage adds the brand where SketchUp shows an icon.

- A toolbar with one Open Panel button. The working assumption is that SketchUp takes vector
  icons as SVG on Windows and PDF on macOS, as the Classify cursor in
  `src/ph_composer/features/zones/faces/cursors/` ships both. Confirm it against the SketchUp
  Ruby API documentation and record the result in the measured host behavior.
- The extension's icon for the Extension Warehouse listing and the release page.
- The mark on the panel's empty states and on the Support dialog, where a mock-up shows it.

This is shipped code. It follows the repository contracts: the architecture review skill, the UI
polish skill for anything inside the HtmlDialog, the runtime manifest refresh, `make ci`, and a
real-host check of the toolbar on macOS. It overlaps the unscheduled
[zones entry points](../zones-entry-points/README.md) packet, whose item E1 asks for a shell
toolbar contribution point so features declare buttons the way they declare menu items. Build
that contribution point once and register the Open Panel button through it.

Needs first: BR-01.
Done when: the toolbar button and icons pass a host check recorded in the native case ledger.

### BR-03. Panel recolour

Apply BR-D9 to the panel's stylesheets.

- In `src/ph_composer/html/base.css`: the interaction-highlight tokens move from teal to espresso;
  `surface-alt`, `line` and `line-strong` move to SketchUp's greys; checked rows take a grey fill
  and a green check.
- Settle BR-O3 before touching the error colour. Warning amber does not change.
- Check every text and control pair for contrast, and check each feature stylesheet for literals
  that repeat the old teal.
- Prototype first in the mockup kit, then browser checks at every panel size, then a host check.

Needs first: Ed's answer to BR-O3 and BR-O8. Phase 7 is editing the same stylesheets, so this
stage should land between Phase 7 stages, not beside one.
Done when: `make ci` passes, the UI gallery is recaptured, and the host check is recorded.

### BR-04. Design System update

Bring the PH-Composer Design System in line once BR-03 has merged.

- New colour tokens and the retirement of the teal ones.
- A Logos asset group with the BR-01 files and a brand section in its README: the mark, the
  product-colour rule, and the split between in-app type and web type.
- A sync receipt naming the commit, as the earlier syncs do.

Needs first: BR-01 and BR-03 merged.

### BR-05. Site scaffold and landing page

A site of PH-Composer's own, separate from the PH-Tools sites.

- A repository under the `ph-composer` organization and a domain (BR-O6).
- Recommended stack: Astro with the Starlight docs theme. The PH-Tools site is already Astro, and
  Starlight's sidebar maps directly onto the four Diátaxis sections.
- A theme from BR-D4 and BR-D7: Figtree and DM Mono self-hosted, espresso text, orange actions
  with white text, the crane illustration as the hero.
- One landing page: what it is, who it is for, an install button, a contribute button, and the
  project's status stated plainly. Copy is written in the BR-D12 voice and checked against the
  repository's README and status.

Needs first: BR-01, BR-O6.
Done when: the site builds, deploys, and the landing page works at phone width.

### BR-06. Beta documentation set

The smallest set a tester needs, published on the BR-05 site.

- **Install and update** (how-to), from `docs/HELP.md`.
- **Your first model** (tutorial): one small house from an empty SketchUp file to an exported
  HBJSON, written new and tested by following it on a clean install.
- **Troubleshooting** (how-to), from `docs/HELP.md`.
- **Report a problem or suggest a change** (how-to): where issues go and what to include.
- **Contribute** (landing section): links to the development guide, the DCO and the security
  policy.

Needs first: BR-05, and BR-O7 for where the tutorial is written.

### BR-07. Full documentation suite

Fill out the [documentation map](#documentation-map) below, one section at a time, after the beta
shows which pages testers reach for.

### BR-08. Links from PH-Tools

Add PH-Composer to the PH-Tools landing page and docs site as a separate project with its own
link. No shared navigation and no PH-Tools branding on the PH-Composer site.

Needs first: BR-05 live.

### BR-09. Video tutorial

A recorded walk through the first-model tutorial, in the manner of the honeybee-ph series.

- Script it from the BR-06 tutorial so the two stay in step.
- Record after the beta interface settles; a recolour or a moved control after recording means
  recording again.
- Title cards and lower thirds use the brand type and the crane illustration.

Needs first: BR-03 merged or deliberately deferred, and BR-06 published.

## Documentation map

The four Diátaxis kinds, with what exists in `docs/` today and what is missing.

| Kind | Purpose | Exists today | To write |
| --- | --- | --- | --- |
| Tutorials | Learning by doing | Nothing | Your first model; a building with several Building Segments; windows and shading; mechanical systems |
| How-to guides | Reaching a goal | `HELP.md`, `SHADING.md`, `AGENT_ACCESS.md`, `API_QUICKSTART.md`, `USER_DATA.md`, `LIBRARY_PROVIDER_EXAMPLE.md`, and the task sections of `PRODUCT.md` | Split `PRODUCT.md` into one page per task; report a problem; set up a library |
| Reference | Looking something up | `API_REFERENCE.md`, `AGENT_GUIDE.md`, `LIBRARY_FILE_FORMAT.md`, `LICENSING.md` | A public glossary from `context/UBIQUITOUS_LANGUAGE.md`; export findings; panel reference |
| Explanation | Understanding why | Nothing public | Why the SKP file owns the model; why library records are copied, not linked; what HBJSON is and what happens after export; how contributions plug in |

Contributor material (`DEVELOPMENT.md`, `DCO.md`, `SECURITY.md` and the `context/` tree) stays in
the repository and is linked from the site, not copied.

Recommendation for BR-O7: how-to and reference pages stay in each product's `docs/`, which this
repository already treats as their owning source, and the site pulls them in at build time.
Tutorials, explanation and the landing page are written in the site's repository, because they
span products. This keeps one source for each page.

## Order and dependencies

```
BR-01 assets ──┬── BR-02 icons in SketchUp
               ├── BR-05 site ── BR-06 beta docs ──┬── BR-08 PH-Tools links
               │                                   ├── BR-07 full docs
BR-03 panel recolour ── BR-04 Design System        └── BR-09 video
```

BR-01 comes first and is small. BR-02 and BR-05 can then run side by side: one is in this
repository, the other in a new one. BR-03 is independent of the site and waits on BR-O3, BR-O8
and a gap in Phase 7.

## What Ed needs to decide before BR-01

1. Product colours (BR-O1), including where a second product's colour comes from (BR-O10).
2. Where the brand assets live (BR-O5).
3. The site's domain (BR-O6), needed by BR-05.
4. Whether the panel recolour is before or after the beta (BR-O8).
