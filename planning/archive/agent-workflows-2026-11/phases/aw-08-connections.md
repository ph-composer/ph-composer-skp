# AW-08 · Repairable client connections

STATUS: Complete. Merged to main (#448, `d204c15e`), API 1.41; host case `AW08` pass; the dialog's native clicks passed in AW-10's `AW10H` run 4. ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/439 (implementation); #435 tracked the review/planning publication.
DEPENDS ON: AW-02 and D02 profile UX choice. FINDING: R11. CONTRACT: C08. ACCEPTANCE: A11.

## Outcome

A user can connect, inspect, reconnect, rotate or repair one client/Model binding without losing
another project's setup or having to rediscover hidden token/configuration rules.

## Work

1. Document exact current supported client versions/configuration capabilities at intake, using local
   clients and current official documentation where needed. Keep macOS-only automation honest.
2. Design saved connection profiles with client, label, endpoint, token binding and optional Model scope.
   Migrate the current fixed entry as the default without changing its permissions. A second profile
   does not silently overwrite it. Make explicit replacement and revocation effects inspectable.
3. Add reconnect/repair from the saved connection. Reuse only an existing live saved credential and
   never display it. Handle old inline-token configuration with a reviewed rotation/migration route.
4. Preserve unowned configuration and concurrent edits. Use the client's supported config tool or a
   precise owned-entry edit; backup and validate changes. Keep a clear manual fallback for formats the
   app cannot safely edit, but do not make harmless extra settings look like failed connection.
5. Report configured/contacted/verified separately. Verify with discovery/context and visible session/
   grants. Diagnose unavailable host, occupied port, revoked token, wrong Model, missing executable
   and client restart requirement. Avoid a model write as a connection test.

## Source and tests

`agent_access/{connections,client_config,client_setup,dialog,listener,tokens}.rb`,
`html/agent_access/page.js`, Setup entry and docs. Extend client config/connection/token tests,
dialog tests and the existing shared browser collector. Cases: two Models/two profiles in one
client, token rotation, old default migration, extra TOML settings, port change, missing binary,
timeout, config modified concurrently, revoked saved file and read-only config. No test reaches
real credentials; logs and previews contain no secret values.

## Native/client gate and done

Fresh GUI-environment sessions of both selected clients connect, read the intended model and respect
scope; changing one profile leaves the other functioning. Revoke and stale/manual fallback messages
are verified. Native dialog at standard/narrow widths and exact OS/client versions recorded. Measure
setup blocking before deciding whether background CLI work is necessary; keep SketchUp calls on the
host thread. Use stronger review for credential/config changes and PLAN's full gates/docs-pass.

No new remote/browser transport, security-posture change or Windows support claim is included.
