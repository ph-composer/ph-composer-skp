# PH-Composer

**DATE:** 2026-10-01 | **STATUS:** Product scope. Phase 1 merged; Phase 2 implemented and accepted on its branch for the current host. Later phases proposed.
**OWNER:** Ed May, BLDGTYP

## Purpose

A free, open-source Passive House authoring environment inside SketchUp for Phius passive
building projects. The consultant defines the building while working with its geometry, keeps
the working data in the SKP file, and exports a complete HBJSON model. A second exporter converts
that HBJSON to the model METr reads.

Hand entry is the normal, complete workflow. No account, hosted project, remote library,
subscription or database service is required to author and export a supported model.

The project exists to be extended. BLDGTYP builds the foundation and the core patterns; anyone can
add a feature, a library provider or an exporter without touching the core.

The accepted [contributor architecture](../context/EXTENSIBILITY.md) also defines scripting,
namespaced metadata and the contracts for record kinds and importers. Phase 0 supplies
registration, record operations and synthetic examples.
Feature-specific and remaining contribution contracts are implementation requirements.

## Product principles

- Users' agents can inspect, view and edit through documented public operations. Agent access is
  a foundation requirement; PH-Composer builds no agent of its own. The planned interface and
  current availability are described in [AGENT_ACCESS.md](AGENT_ACCESS.md).

- The SKP file carries authored definitions, instances, assignments and values, including unused
  definitions deliberately retained for this building. Moving the file to another computer
  preserves model authoring without resolving external library records.
- Bookshelfing copies a library record into the model. The user can edit that copy locally. Source
  attribution does not give a provider authority over the working model.
- Library providers are optional and interchangeable. A folder of files on disk, a firm's server
  and a vendor catalog all answer the same contract. None is a default the software ships.
- Geometry-linked work happens in SketchUp. Tables and graphical editors make non-geometric
  definitions and schedules equally accessible in the extension.
- Model validation explains problems with the authored building and its export. Certification
  evidence status, review conversations and project tracking belong downstream.
- User actions preserve clear references, explicit change scope, recoverability and native Undo.
- A supported feature includes a trustworthy export of its relevant data. Unrepresentable content
  is disclosed; storing something locally does not prove a downstream consumer can use it.
- The UI is a kit other teams can reuse. It carries no calculation and no honeybee dependency.

## People and jobs

The primary user is a Phius CPHC authoring a building model in SketchUp for METr. An individual
works entirely locally; a firm may curate shared starting definitions through a library provider.
A recipient uses HBJSON or the METr model without becoming an upstream authoring dependency.
BLDGTYP is the first internal user.

A second audience is contributors: consultants and developers who add a feature, a provider or an
exporter. The contributor architecture names the supported kinds of contribution and their contracts.

## Proposed feature scope

The phase numbers follow the proposed roadmap and are not implementation authorization.
Phase 1 is merged. Phase 2 Assemblies, file libraries and Windows are implemented and accepted
on the feature branch within Current capability below. The core seam for hosted libraries that sign
in is implemented; the extensions that connect to a hosted library, and later phases, remain proposed.

| Phase | Feature | User outcome |
| --- | --- | --- |
| 1 | Zones and adjacency | Define the geometry units, Building-Segments and Levels; solve or explicitly classify interior relationships |
| 1 | Face assignment | Classify envelope faces by face type and boundary condition; stable through Undo, save and nested contexts |
| 1 | Validation and export | Produce canonical HBJSON and a coordinated report with complete accounting; METr exporter deferred to a later milestone |
| 2 | Assemblies and materials | Graphically build layered assemblies; enter, reuse, edit and assign model-local materials and assemblies |
| 2 | Optional library import | Copy curated definitions from interchangeable file providers into editable model-local records; connections remain Phase 5 |
| 2 | Window Types and placement | Compose Window Types from Frames, Glazings and Psi-Install Types; place and resize window units on classified envelope faces |
| 3 | Spaces and airflows | Author Spaces and Volumes, classify iCFA floors, and enter ventilation rates. Space Types remain later scope |
| 3 | Thermal bridges | Identify linear thermal bridges on the model and assign psi-values. Point bridges and chi-values are not part of the MVP |
| 4 | Equipment | Author ventilators, heat pumps, pumps, fans, hot-water tanks and heaters, electrical heaters and appliances |
| 4 | Piping and ducting | Describe measured runs and their system relationships using honeybee-ph concepts |
| 5 | Climate and site | Author or import site and climate data. Accept user-owned monthly files and local EPWs converted to a model-owned monthly snapshot; ship no datasets. METr export additionally requires user-supplied peak-load climate data |
| Later | Space Types | Maintain a local collection of reusable Space definitions |
| Later | PV | Add the renewable data supported by the canonical export stack |
| Later | Optional linked evidence | Open and repair links from records to external PDFs and photos |
| Later | Optional transmission package | Share a fixed model and its selected linked evidence together |

Agreed behaviors carried over from the predecessor's interviews, which still hold because they do
not depend on designPH, are in [PRODUCT.md](PRODUCT.md).

## Storage and portability

The SKP is the primary datastore for the authored building. Attribute dictionaries are the storage
mechanism, with the record pattern the predecessor settled. Local preferences and rebuildable
caches may live outside the model; they must not contain the only copy of building data.

PDF and photo bytes remain external. The model may store optional references to them. A missing
linked file does not prevent model editing, calculation or ordinary export.

## Integration boundaries

- honeybee-ph supplies the domain vocabulary and the typed export structures. Face types and
  boundary conditions are honeybee's; PH-Composer does not coin a third vocabulary.
- PHX will convert HBJSON to the METr model, running inside the shipped runtime as the first
  exporter. That exporter is deferred; the shipped runtime carries only the HBJSON translation
  stack today. The extension does not operate Excel and does not write PHPP.
- METr is the calculator. PH-Composer produces its input and claims nothing about its results.
- PassivSure is a sibling project building a PHI-focused designPH companion. It may reuse the UI
  kit and the record engine. It is not a destination for PH-Composer's output.
- PH-Navigator web is prior art for editors, tables and calculations, and one library provider
  among several. It is not a required service.
- The predecessor, PH-Navigator for SketchUp, is prior art and evidence. Its designPH integration
  is retired.

## Exclusions

No designPH integration, no PHI certification workflow and no PHPP export. No hosted datasheet or
photo storage, specification-status editor, certification roadmap, hosted climate map, bundled or redistributed climate datasets, built-in
model viewer, review conversation or automatic model-version service. Local climate files,
manual entry and EPW-derived monthly climate are post-MVP scope. No HBJSON-to-SketchUp reconstruction. Optional
linked evidence is in proposed scope and adds none of those services.

## Managed Zone options

Building Segment and Level use Model-owned choices with editable names and colours. Their column
menus open the management dialog; Save applies a complete draft and Cancel discards it. Rename
keeps assignments. Merge/removal replaces used choices explicitly, including recoverable Zone
members; Level may be cleared to Not set. Older Models show an adoption preview before category
management, with explicit choices for equivalent names and copied definitions. Required current-host functional cases
and final normal source-panel visual restoration passed. The addition merged through PR #80.

## Current capability and release boundary

The foundation merged through PR #1: records and public operations, sessions, panel/UI kit and
shared units, the runtime shell and export infrastructure. Phase 1 merged on
2026-09-30: Zones, Faces and the adjacency between them, the Classify tool, Auto-classify,
Attached zones, Colour-by, the Zones / Faces screen, copy and split repairs, the public scripting
interface, and the export run to canonical HBJSON and its report. Export needs authored
Assemblies. Phase 2 supplies authored Materials and Assemblies, file libraries, Window Types and
placed Units on its feature branch, accepted on SketchUp 26.1.188/macOS. The normal packaged
build exports resolved opaque constructions and Apertures without a development provider.
Phase 1 historical export proof used a development-only construction provider. Merging is separate from any release. METr
export and import acceptance are deferred until further feature development; their return
milestone is unscheduled.

SketchUp 2023 is the compatibility floor; its host proof is pending. SketchUp 26.1.188 on macOS
is the proving host. Windows support and public distribution are separate gates. The first
public release subset is undecided.

## How scope becomes implementation

Review one feature at a time in short interview rounds. Each feature plan records seed stories,
unanswered decisions, actual answers and Ed's confirmation. Recommendations are not accepted
decisions. A proposed implementation plan may identify unresolved gates, but dependent work
waits for those decisions and a separate instruction to implement.
