# EUD-10: final review, merge and archive

STATUS: Scoped
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)

## Steps

1. `make ci` on the final head; one Codex review (gpt-6.1-sol) over the combined diff, posted to the
   PR; fix and answer every thread (two cycles at most).
2. EUD-09 on the head that goes to merge.
3. Under `--merge`: read the checks once; merge on green, or arm auto-merge.
4. Archive per `planning-conventions`: fold durable outcomes into `context/`, move the packet to
   `planning/archive/entity-user-data/`, add the row to `planning/archive/README.md`, fix links.
   The archive commit says `Closes #507`.
