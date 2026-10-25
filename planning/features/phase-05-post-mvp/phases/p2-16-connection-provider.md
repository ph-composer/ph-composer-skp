# P2-16: connection provider and sign-in

DATE: 2026-09-30
STATUS: Scoped. Authorized 2026-10-01; preceding stage gates remain required.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/14

## Entry and scope

Requires P2-15. Ed confirmed on 2026-09-30 (D2-8) that this stage is decided when P2-15 closes: it
runs in Phase 2 only if the PH-Navigator endpoint serves the neutral envelope by then; otherwise
this document moves with roadmap item 2.5 to Phase 5 unchanged. It also waits on the PH-Navigator endpoint
serving the neutral envelope, which is work in another repository.

Owns the second provider: one generic connection the user points at an address, and the
one-page protocol. Nothing specific to any vendor enters the code and no address ships.

Behavior owner: [libraries PRD](../../../archive/libraries/PRD.md), "The connection protocol" and "Security
rules", Q6, Q7, Q16, Q18. Host rules: `context/TECH_STACK.md`, "The library provider seam".

Predecessor paths are relative to `../../ph-navigator-sketchup/src/ph_navigator_sketchup/` at
`f358ebf`.

## Steps

1. **Protocol page.** `docs/LIBRARY_CONNECTION_PROTOCOL.md`: `GET /library`,
   `GET /library/<kind>` returning the library file envelope, and the auth discovery document.
   Read only. Client-facing register, no dashes.
2. **Transport.** Port `runtime/http.rb` and `features/organization_library/transport.rb` over
   `Sketchup::Http::Request`: a single-shot timer as the timeout, every request retained until it
   finishes, HTTPS or loopback only. Callbacks publish catalog state through the host-safe
   boundary and never mutate a Model or open the panel.
3. **Credentials.** Port `credentials.rb`: the macOS Keychain through one short-lived process
   with the secret as an argument. Windows credential storage is unproven and stays its own gate.
4. **Connection provider.** Port `connection.rb` as a provider registered through
   `library_provider`: discovery, the three sign-in methods (none, static token, device-code
   approval), and the named states. A static token is typed into a native Ruby input box. The
   address is entered in a native dialog. Neither crosses the panel boundary. Only a summary of
   host name and booleans reaches the panel.
5. **Generations and lateness.** Discovery and list results carry the configuration revision and
   catalog generation. A late response after reconfiguration, removal or session disposal is
   ignored. An ordinary offline failure keeps the loaded generation usable; revocation or removal
   discards it.
6. **Refusals.** A catalog body that echoes the token or the address is refused before any field
   becomes data. A plain HTTP address that is not loopback is refused.
7. **Setup and states in the panel.** Add "Add connection..." to the setup surface and the
   connection states to the sidebar wording.
8. **Test server.** Port `tools/hostkit/library_server.py` to serve the neutral envelope with
   each sign-in method, and a static file host case.

## Source

| Predecessor file | Lines | Disposition |
| --- | --- | --- |
| `features/organization_library/{connection,transport,credentials}.rb`, `runtime/http.rb` | 527 | Port as the generic connection |
| `tests/connection_test.rb`, `credentials_test.rb`, `transport_test.rb`, `tests/support/credentials_runner.rb` | about 405 | Port |
| `tools/hostkit/library_server.py`, `tests/test_library_server.py` | 271 | Adapt to the neutral envelope |

## Tests (write first)

1. The provider contract module from P2-07 passes against the connection with a stubbed
   transport.
2. Each sign-in method and each named state.
3. A late response after removal changes nothing; offline keeps the catalog; revocation drops it.
4. A token-echoing body and a non-loopback HTTP address refuse.
5. No credential or address appears in a snapshot, a log, an outcome, the SKP or an export.

## Host gate

Fresh process against the local test server: each sign-in method, a static file host as a
server, copy a record, go offline and copy again from the loaded catalog, revoke and see the
catalog dropped. Then, when it exists, the PH-Navigator endpoint as one more address.

## Out of scope

Windows credentials. Any write endpoint. A default address.

## Done when

- E16 has evidence in `evidence/p2-16-connection.md`, or D2-8 has moved the row to Phase 5.
- The libraries packet STATUS records 2.5.
