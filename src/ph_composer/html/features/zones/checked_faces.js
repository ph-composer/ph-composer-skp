/* The Faces checked in the Zones tab's Faces view: the set a bulk assignment acts on.
 *
 * The set belongs to the panel. It can span Zones, and checking a row never changes SketchUp's selection,
 * because SketchUp's selection holds only entities in the open edit context, so a mirrored set could not
 * span Zones (context/SKETCHUP_HOST_BEHAVIOR.md). The sync runs one way: when SketchUp's selection changes,
 * the set is replaced by the Faces now selected there, and a selection with no Faces in it (nothing, or a
 * Group) clears it. The host counts selection changes, because the Faces alone cannot tell a change from no
 * change: a Group selected and then nothing reads as no Faces both times.
 *
 * A Face is keyed by its occurrence (its Zone's path and its own), not its record id: a Face gains a record
 * when it is first classified, which must not uncheck it. A row with no Faces that the view lets check itself
 * (a Zone with no Faces, so it can still be moved) is kept by its row key in `rows`, and goes with the Faces:
 * a range, a replacement and a clear treat it as they treat them.
 */
PhComposerUI.define("features/zones/checked_faces", [], function () {
  "use strict";

  function key(reference) {
    return JSON.stringify([reference.zone_path || [], reference.entity_path || []]);
  }

  /* The Faces a row stands for: a Face row its Face, a Zone row every Face under it, a summary row the
     unclassified Faces it heads. "Show all" stands for none. */
  function facesOf(row) {
    if (row.record.face) return [row.record.face];
    if (row.record.more) return [];
    return row.record.every || row.record.faces || [];
  }

  function CheckedFaces() {
    this.keys = Object.create(null);
    this.rows = Object.create(null);
    this.anchor = null;
    this.synced = undefined;
  }

  CheckedFaces.prototype.rowChecked = function (row) { return Boolean(this.rows[row.key]); };

  /* The checked rows with no Faces, kept only where `live` (row key to row) still has them. */
  CheckedFaces.prototype.keepRows = function (live) {
    var rows = this.rows;
    this.rows = Object.create(null);
    Object.keys(rows).forEach(function (rowKey) { if (live[rowKey]) this.rows[rowKey] = true; }, this);
    return Object.keys(this.rows).map(function (rowKey) { return live[rowKey]; });
  };

  CheckedFaces.prototype.checkRows = function (rowKeys) {
    rowKeys.forEach(function (rowKey) { this.rows[rowKey] = true; }, this);
  };

  CheckedFaces.prototype.has = function (face) { return Boolean(this.keys[key(face.reference)]); };

  /* true, false or "mixed" for a row with Faces under it; null for one with none, which has no box. */
  CheckedFaces.prototype.state = function (row) { return this.stateOf(facesOf(row)); };

  CheckedFaces.prototype.stateOf = function (faces) {
    if (!faces.length) return null;
    var count = faces.filter(this.has, this).length;
    return count === 0 ? false : count === faces.length ? true : "mixed";
  };

  CheckedFaces.prototype.set = function (faces, checked) {
    faces.forEach(function (face) {
      if (checked) this.keys[key(face.reference)] = true;
      else delete this.keys[key(face.reference)];
    }, this);
  };

  /* A click checks the row's Faces, or unchecks them when they all are; a row that checks itself (`itself(row)`)
     checks or unchecks itself. Shift-click applies the same to every row between the last box clicked and this
     one, in the order the table shows them. */
  CheckedFaces.prototype.toggle = function (row, event, shown, itself) {
    itself = itself || function () { return false; };
    var checked = itself(row) ? !this.rowChecked(row) : this.state(row) !== true;
    var keys = shown.map(function (entry) { return entry.key; });
    var from = event && event.shiftKey && this.anchor ? keys.indexOf(this.anchor) : -1;
    var to = keys.indexOf(row.key);
    var rows = from >= 0 && to >= 0 ? shown.slice(Math.min(from, to), Math.max(from, to) + 1) : [row];
    rows.forEach(function (entry) {
      if (!itself(entry)) this.set(facesOf(entry), checked);
      else if (checked) this.rows[entry.key] = true;
      else delete this.rows[entry.key];
    }, this);
    this.anchor = row.key;
  };

  /* The header box checks every Face the table shows, or unchecks them when they all are. */
  CheckedFaces.prototype.toggleAll = function (faces) {
    this.set(faces, this.stateOf(faces) !== true);
    this.anchor = null;
  };

  CheckedFaces.prototype.replace = function (references) {
    this.keys = Object.create(null);
    this.rows = Object.create(null);
    references.forEach(function (reference) { this.keys[key(reference)] = true; }, this);
    this.anchor = null;
  };

  CheckedFaces.prototype.clear = function () { this.replace([]); };

  /* The checked Faces among `faces`, so a Face the Model no longer has is never counted or assigned. */
  CheckedFaces.prototype.among = function (faces) { return faces.filter(this.has, this); };

  /* Replaces the set when SketchUp's selection has changed since the last time: `generation` is the host's count
     of selection changes. Without one (a host that does not publish it), a different set of selected Faces,
     in whatever order the host lists them, is the change. Answers whether it replaced the set. */
  CheckedFaces.prototype.sync = function (targets, generation) {
    var references = targets.map(function (target) { return target.reference || {}; });
    var signature = typeof generation === "number" ? "generation:" + generation : references.map(key).sort().join("|");
    if (signature === this.synced) return false;
    this.synced = signature;
    this.replace(references);
    return true;
  };

  return CheckedFaces;
});
