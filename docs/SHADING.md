# Shading surfaces

Neighbouring buildings, trees, fins and overhangs shade the building. Tag their Faces, Groups or
components as shading and PH-Composer treats every Face inside them as a shading surface. Shading
is opaque: there is nothing else to set.

## Tag and clear

Select the Faces, Groups or components, then choose **Set as Shading** from the PH-Composer
right-click menu or from Extensions > PH-Composer. **Clear Shading** removes the tag the same way.

- Each choice is one Undo step.
- Edges and other entities in the selection are ignored, and the message says how many.
- A mixed selection tags what it can and names what it left out and why, in the PH-Composer
  notice and the status bar. Nothing is written only when nothing in the selection can be tagged.
- Tagging a Group or component makes every Face inside it a shading surface, at any depth. Tag
  the container, not each Face.
- Clear removes the tag from the selected entity only. A Face that is shading because its Group is
  tagged stays shading, and the message names the Group to clear instead.
- The right-click menu offers Set as Shading only when something selected can take the tag, and
  Clear Shading only when something selected carries one.

## What can be tagged

| Selection | Result |
| --- | --- |
| A loose Face, at the Model root or inside a plain Group or a component placed once | Tagged |
| A plain Group or component, at the root, nested, or inside a Zone | Tagged, with every Face inside it |
| A Group or component inside a Zone that holds classified Faces | Left out. Clear those Faces' classification first |
| An unclassified Face inside a Zone, such as an overhang | Tagged. It leaves the Zone's envelope and is no longer an unclassified Face |
| A classified Face inside a Zone | Left out. Clear its classification first |
| A Face inside a component placed more than once, or inside a copied Group not yet made unique | Left out. Tag the component or Group instead, or make it unique first |
| A Zone, or a Group that holds one | Left out |
| A Space, a Volume, a Floor Segment, anything inside one, or a Group that holds one | Left out |
| A Window Unit, its pane Faces, or any Face inside a cutting component | Left out |
| Anything inside a locked Group or component | Left out |

## Names

PH-Composer groups shading surfaces into shading components by name. The name comes from the
nearest enclosing Group or component that has one. Inside a Zone with no named Group in between,
the name is the Zone's name followed by " Shading". With no named container, the name is
"Shading". Two Groups with the same name make one component, so rename a Group to split it out.

## See what is tagged

Choose **Colour by > Shading** from Extensions > PH-Composer. Every shading surface takes its
component's colour, including Faces inside tagged Groups and each placement of a tagged component.
Everything else keeps its SketchUp colour. The legend in the upper left lists each component with
its Face count and area in the Model's display units. A Face hidden by a tag stops drawing but
still counts in the legend. A component placed with a scale that flattens it shows in amber with no
area.

## Scripts and agents

Set as Shading and Clear Shading call the same actions a script or a connected agent uses:
`ph_composer.shading.selection` reads the selection, and `ph_composer.shading.assign` and
`ph_composer.shading.clear` write. See the [API reference](API_REFERENCE.md).
