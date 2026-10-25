# Security policy

## Reporting a vulnerability

Report a security problem privately through GitHub's private vulnerability reporting:
https://github.com/ph-composer/ph-composer-skp/security/advisories/new

Do not open a public issue for a security problem. A public issue is visible to everyone before a
fix exists.

Include:

- the build, from Help & Diagnostics;
- the SketchUp version and the platform;
- the steps that show the problem;
- whether an agent token or a library file is involved.

Never attach a client Model. Reproduce the problem with a new, empty Model where you can.

## What is in scope

The shipped extension, the `.rbz`:

- the panel and its dialogs;
- the loopback agent listener and its tokens;
- the export runtime and its local asset server;
- file reads and writes through approved locations and library folders.

The development tooling under `tools/` never ships and is out of scope.

## Supported versions

Until the first release, `main` is supported. After it, the latest release is supported.

## What to expect

We acknowledge a report within seven days. A confirmed problem is fixed, or the decision not to
change it is documented, in the next release.
