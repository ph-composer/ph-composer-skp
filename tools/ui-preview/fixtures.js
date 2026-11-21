/* The preview's synthetic Models, chosen with `?fixture=<name>`. Synthetic values only. */
(function (global) {
  "use strict";

  var PARTS = [
    { id: "exp_Aa11Bb22Cc33", label: "Sill", length_mm: 1200 },
    { id: "exp_Dd44Ee55Ff66", label: "Head", length_mm: 1231.9 },
    { id: "exp_Gg77Hh88Ii99", label: "Jamb", length_mm: 2438.4 }
  ];
  function zonePath(id) { return id === "zon_Aa11Bb22Cc33" ? [100] : [200]; }
  function zone(id, name, level, faceCount) {
    return { id: id, schema_version: 1, user_data: {}, extension_data: {},
      reference: { zone_id: id, zone_path: zonePath(id) }, state: "found", face_count: faceCount,
      values: { name: name, building_segment: "House", level: level, ground_depth_mm: 0 } };
  }
  function face(zoneId, path, id, area, values, state) {
    return { reference: { zone_id: zoneId, zone_path: zonePath(zoneId), entity_path: [path], entity_id: id },
      zone_name: "", area_m2: area, values: values, state: state,
      suggested: { face_type: "Wall", boundary_condition: "Outdoors" } };
  }
  // Two Zones, so the tree has something to be a tree of: one fully classified, one with an
  // incomplete Face and two the user has not reached yet.
  var AUTHORING = {
    zones: [zone("zon_Aa11Bb22Cc33", "Living Zone", "Ground", 3),
      zone("zon_Dd44Ee55Ff66", "Attic Zone", "Upper", 3)],
    faces: [
      face("zon_Aa11Bb22Cc33", 101, "fac_Aa11Bb22Cc33", 12,
        { id: "fac_Aa11Bb22Cc33", face_type: "Wall", boundary_condition: "Outdoors" }, "classified"),
      face("zon_Aa11Bb22Cc33", 102, "fac_Dd44Ee55Ff66", 20.5,
        { id: "fac_Dd44Ee55Ff66", face_type: "Floor", boundary_condition: "Ground" }, "classified"),
      face("zon_Aa11Bb22Cc33", 103, null, 8, {}, "unclassified"),
      face("zon_Dd44Ee55Ff66", 201, "fac_Gg77Hh88Ii99", 31.25,
        { id: "fac_Gg77Hh88Ii99", face_type: "RoofCeiling", boundary_condition: "Surface" }, "classified"),
      face("zon_Dd44Ee55Ff66", 202, "fac_Jj00Kk11Ll22", 14,
        { id: "fac_Jj00Kk11Ll22", face_type: "Wall" }, "incomplete"),
      face("zon_Dd44Ee55Ff66", 203, null, 9, {}, "unclassified")
    ]
  };

  var FIXTURES = {
    inventories: {
      "parts": [],
      "materials": {
        "records": [
          {
            "id": "mat_a",
            "kind": "ph_composer.assemblies.material",
            "schema_version": 1,
            "user_data": {},
            "extension_data": {},
            "values": {
              "name": "Mineral wool",
              "notes": "",
              "category": "insulation",
              "color": "#fff2cc",
              "conductivity_w_mk": 0.04,
              "density_kg_m3": 30,
              "specific_heat_j_kgk": 1000,
              "emissivity": 0.9
            },
            "findings": [],
            "uses": [
              {
                "assembly_id": "asm_a",
                "name": "Wall"
              }
            ],
            "use_count": 1
          },
          {
            "id": "mat_b",
            "kind": "ph_composer.assemblies.material",
            "schema_version": 1,
            "user_data": {},
            "extension_data": {},
            "values": {
              "name": "Wood",
              "notes": "",
              "category": "woods",
              "color": "#c69c6d",
              "conductivity_w_mk": 0.12,
              "density_kg_m3": 500,
              "specific_heat_j_kgk": 1500,
              "emissivity": null
            },
            "findings": [],
            "uses": [],
            "use_count": 0
          }
        ],
        "unreadable": [],
        "categories": [
          {
            "id": "insulation",
            "label": "Insulation",
            "tone": "warm"
          },
          {
            "id": "woods",
            "label": "Woods",
            "tone": "wood"
          }
        ]
      },
      "assemblies": {
        "records": [
          {
            "id": "asm_a",
            "kind": "ph_composer.assemblies.assembly",
            "schema_version": 1,
            "user_data": {},
            "extension_data": {},
            "values": {
              "name": "Wall",
              "notes": "",
              "color": "#c5e1a5",
              "type": "Wall",
              "exterior_condition": "Outdoors"
            },
            "findings": [],
            "display": {
              "total_thickness_mm": 200,
              "thermal": {
                "complete": true,
                "u_effective_w_m2k": 0.2,
                "warnings": []
              }
            }
          },
          {
            "id": "asm_b",
            "kind": "ph_composer.assemblies.assembly",
            "schema_version": 1,
            "user_data": {},
            "extension_data": {},
            "values": {
              "name": "Incomplete roof",
              "notes": "",
              "color": "#bbdefb",
              "type": "RoofCeiling",
              "exterior_condition": "Outdoors"
            },
            "findings": [],
            "display": {
              "total_thickness_mm": 100,
              "thermal": {
                "complete": false,
                "u_effective_w_m2k": null,
                "warnings": [
                  "Choose a Material for every Layer-Segment."
                ]
              }
            }
          }
        ],
        "unreadable": []
      },
      "attachedZones": [
        {
          "id": "atz_a",
          "values": {
            "name": "Garage",
            "kind": "garage",
            "temperature_reduction_factor": 0.95
          }
        }
      ]
    },
    parts: { parts: PARTS },
    empty: { parts: [] },
    // A German regional format: comma decimals and point grouping in what the user types and reads.
    regional: { parts: PARTS, locale: "de-DE", decimal: "," },
    ip: { parts: PARTS, unitSystem: "IP" },
    authoring: { parts: [], zones: AUTHORING.zones, faces: AUTHORING.faces,
      attachedZones: [{ kind: "ph_composer.zones.faces.attached_zone", id: "atz_Aa11Bb22Cc33",
        values: { name: "Garage", kind: "garage", temperature_reduction_factor: 0.95 } }] }
  };

  /* The Thermal Bridges tab: three types (one still without a psi-value), the two authoring Zones, three runs
     and an assigned Edge no Zone holds, and three Edges selected in the Living Zone, one already assigned. */
  function tbType(id, name, psi, group, color) {
    return { id: id, kind: "ph_composer.thermal_bridges.type", schema_version: 1, user_data: {}, extension_data: {},
      findings: [], values: { name: name, notes: "", datasheet_links: [], psi_w_mk: psi, group: group },
      display: { color: color }, export_ready: psi !== null, export_blockers: psi === null ?
        ["thermal_bridge.psi_missing"] : [] };
  }
  function tbRun(id, name, zone, typeId, length, paths, findings) {
    return { identifier: id, display_name: name, zone: zone, type_id: typeId, quantity: 1, length_m: length,
      closed: false, points_m: [], shared: false, findings: findings || [], edge_paths: paths };
  }
  var LIVING = { zone_id: "zon_Aa11Bb22Cc33", zone_path: [100], name: "Living Zone", building_segment: "House" };
  var ATTIC = { zone_id: "zon_Dd44Ee55Ff66", zone_path: [200], name: "Attic Zone", building_segment: "House" };
  function selectedEdge(id, values) {
    return { path: [100, id], reference: { zone_id: LIVING.zone_id, zone_path: [100], entity_path: [id],
      entity_id: values ? "tbe_Aa11Bb22Cc3" + (id % 10) : null }, zone: Object.assign({ level: "Ground" }, LIVING),
      reason: null, values: values || {}, copied: false, record_problem: null, write_refusal: null };
  }
  FIXTURES.thermalbridges = { parts: [], zones: AUTHORING.zones, faces: AUTHORING.faces, thermalBridges: {
    types: [tbType("tbt_Aa11Bb22Cc33", "Parapet", 0.12, "15-Ambient", "#c8553d"),
      tbType("tbt_Dd44Ee55Ff66", "Slab edge", -0.02, "17-FS/BC", "#6a8eae"),
      tbType("tbt_Gg77Hh88Ii99", "Balcony", null, "15-Ambient", "#d9a23b")],
    selected: [selectedEdge(301, { thermal_bridge_type_id: "tbt_Aa11Bb22Cc33", quantity: 1 }), selectedEdge(302),
      selectedEdge(303)],
    runs: [tbRun("tb_Aa11Bb22Cc33", "Parapet 1", LIVING, "tbt_Aa11Bb22Cc33", 18,
      [[100, 301], [100, 302], [100, 303], [100, 304]]),
    tbRun("tb_Dd44Ee55Ff66", "Parapet 2", ATTIC, "tbt_Aa11Bb22Cc33", 16, [[200, 401], [200, 402]],
      [{ code: "thermal_bridge.coincident_conflict", blocks_export: false,
        message: "1 Edge is also assigned in Attic with a different Thermal Bridge Type, " +
          "so both are counted; clear one.",
        locate: { edge_paths: [[200, 401]] } }]),
    tbRun("tb_Gg77Hh88Ii99", "Slab edge 1", LIVING, "tbt_Dd44Ee55Ff66", 18, [[100, 311], [100, 312]])],
    edgeFindings: [{ path: [5], code: "thermal_bridge.outside_zone", blocks_export: false,
      message: "An assigned Edge is not inside a Zone, so it is not exported. Move it into a Zone or clear it.",
      locate: { edge_paths: [[5]] } }] } };

  // Public synthetic Builder reference. Thermal fields are fixed canonical host responses.
  FIXTURES.builder = JSON.parse(JSON.stringify(FIXTURES.inventories));
  [FIXTURES.inventories, FIXTURES.builder].forEach(function (fixture) {
    fixture.assemblies.records.forEach(function (record, index) {
      record.values.orientation = "first_layer_outside";
      record.values.air_barrier = null;
      record.values.ventilated_cladding = false;
      record.values.layers = [{ id: "lyr_board_" + index, thickness_mm: 12,
        segments: [{ id: "seg_board_" + index, width_mm: 600, material_id: "mat_b",
          is_continuous_insulation: false, steel_stud_spacing_mm: null }] },
      { id: "lyr_studs_" + index, thickness_mm: 140, segments: [
        { id: "seg_wool_" + index, width_mm: 560, material_id: "mat_a",
          is_continuous_insulation: false, steel_stud_spacing_mm: null },
        { id: "seg_stud_" + index, width_mm: 40, material_id: index ? null : "mat_b",
          is_continuous_insulation: false, steel_stud_spacing_mm: 600 }] },
      { id: "lyr_lining_" + index, thickness_mm: 13,
        segments: [{ id: "seg_lining_" + index, width_mm: 600, material_id: "mat_b",
          is_continuous_insulation: false, steel_stud_spacing_mm: null }] }];
      record.display.total_thickness_mm = 165;
      record.display.thermal.u_construction_w_m2k = index ? null : 0.21;
      record.display.thermal.rsi_m2k_w = 0.13;
      record.display.thermal.rse_m2k_w = 0.04;
      record.display.thermal.direction = "horizontal";
    });
  });

  FIXTURES.assignment = JSON.parse(JSON.stringify(FIXTURES.inventories));
  FIXTURES.assignment.zones = JSON.parse(JSON.stringify(AUTHORING.zones));
  FIXTURES.assignment.faces = JSON.parse(JSON.stringify(AUTHORING.faces));
  FIXTURES.assignment.faces.forEach(function (face, index) {
    if (face.values.face_type) face.values.assembly_id = index % 2 ? "asm_b" : "asm_a";
  });
  FIXTURES.assignment.selectedFaces = FIXTURES.assignment.faces.filter(function (face) {
    return face.values.face_type;
  }).slice(0, 2).map(function (face) { return face.reference; });

  FIXTURES.libraries = JSON.parse(JSON.stringify(FIXTURES.builder));
  FIXTURES.libraries.libraryProviders = [{ id: "synthetic", provider_kind: "ph_composer.library.file",
    label: "Synthetic library", kinds: ["materials"] }, { id: "other", provider_kind: "example.provider",
    label: "Other provider", kinds: ["materials"] }];
  FIXTURES.libraries.librarySetupState = "readable";
  FIXTURES.libraries.libraryCatalogs = { synthetic: [
    { library_id: "public.insulation", library_name: "Public insulation", record_id: "new", wire_schema_version: 1,
      snapshot: { id: "new", name: "Synthetic fiber", category: "insulation", conductivity_w_mk: 0.045,
        density_kg_m3: 45, specific_heat_j_kgk: 1400, emissivity: 0.8, color: "#ddeedd",
        notes: "Synthetic public source", datasheet_links: [] } },
    { library_id: "public.insulation", library_name: "Public insulation", record_id: "review", wire_schema_version: 1,
      snapshot: { id: "review", name: "Mineral wool", category: "insulation", conductivity_w_mk: 0.04,
        density_kg_m3: 55, specific_heat_j_kgk: 1000, emissivity: 0.9, color: "#fff2cc",
        notes: "Revised library notes", datasheet_links: [] } }
  ], other: [] };
  // A copied definition whose local and incoming links are both populated, for comparison review.
  FIXTURES.copylinks = JSON.parse(JSON.stringify(FIXTURES.libraries));
  FIXTURES.copylinks.materials.records[0].values.datasheet_links = ["https://example.com/local.pdf"];
  FIXTURES.copylinks.libraryCatalogs.synthetic[1].snapshot.datasheet_links = ["https://example.com/revised.pdf"];

  // The Builder reference with five uneven Layers, one a membrane, for dragging whole Layers.
  FIXTURES.layerdrag = JSON.parse(JSON.stringify(FIXTURES.builder));
  FIXTURES.layerdrag.materials.records.push(Object.assign(JSON.parse(JSON.stringify(
    FIXTURES.builder.materials.records[1])), { id: "mat_m", uses: [], use_count: 0 }));
  Object.assign(FIXTURES.layerdrag.materials.records[2].values, { name: "Membrane", category: "membrane",
    color: "#90a4ae", conductivity_w_mk: null });
  FIXTURES.layerdrag.assemblies.records[0].values.layers.splice(2, 0,
    { id: "lyr_membrane_0", thickness_mm: 1, segments: [{ id: "seg_membrane_0", width_mm: 600, material_id: "mat_m",
      is_continuous_insulation: false, steel_stud_spacing_mm: null }] },
    { id: "lyr_insulation_0", thickness_mm: 50, segments: [{ id: "seg_insulation_0", width_mm: 600,
      material_id: "mat_a", is_continuous_insulation: true, steel_stud_spacing_mm: null }] });

  FIXTURES.windows = JSON.parse(JSON.stringify(FIXTURES.inventories));
  FIXTURES.windows.windows = {
  "types": {
    "records": [
      {
        "id": "wnt_a",
        "values": {
          "name": "Three elements",
          "notes": "",
          "rows_m": [
            1.5
          ],
          "columns_m": [
            0.5,
            0.5,
            0.5
          ],
          "elements": [
            {
              "id": "wel_a",
              "name": "Element 1",
              "kind": "glazed",
              "row_span": [
                0,
                0
              ],
              "column_span": [
                0,
                0
              ],
              "glazing_id": "glz_a",
              "frames": {
                "top": "frm_a",
                "right": "frm_a",
                "bottom": "frm_a",
                "left": "frm_a"
              },
              "installs": {
                "top": null,
                "right": null,
                "bottom": null,
                "left": null
              },
              "operation": {
                "type": "fixed",
                "directions": []
              }
            },
            {
              "id": "wel_b",
              "name": "Element 2",
              "kind": "glazed",
              "row_span": [
                0,
                0
              ],
              "column_span": [
                1,
                1
              ],
              "glazing_id": "glz_a",
              "frames": {
                "top": "frm_a",
                "right": "frm_a",
                "bottom": "frm_a",
                "left": "frm_a"
              },
              "installs": {
                "top": null,
                "right": null,
                "bottom": null,
                "left": null
              },
              "operation": {
                "type": "fixed",
                "directions": []
              }
            },
            {
              "id": "wel_c",
              "name": "Element 3",
              "kind": "empty",
              "row_span": [
                0,
                0
              ],
              "column_span": [
                2,
                2
              ],
              "glazing_id": null,
              "frames": {
                "top": null,
                "right": null,
                "bottom": null,
                "left": null
              },
              "installs": {
                "top": null,
                "right": null,
                "bottom": null,
                "left": null
              },
              "operation": null
            }
          ]
        },
        "user_data": {},
        "extension_data": {},
        "findings": [],
        "display": {
          "width_m": 1.5,
          "height_m": 1.5,
          "install_depth_m": 0.1,
          "thermal": {
            "uw_w_m2k": 0.8,
            "u_effective_w_m2k": 0.9,
            "complete": true,
            "area_m2": 1.5,
            "empty_area_m2": 0.75,
            "findings": [],
            "elements": [
              {
                "id": "wel_a",
                "uw_w_m2k": 0.8,
                "findings": [],
                "edges": [
                  {
                    "side": "top",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  },
                  {
                    "side": "right",
                    "length_m": 0.5,
                    "install": {
                      "source": "shared",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  },
                  {
                    "side": "bottom",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  },
                  {
                    "side": "left",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  }
                ]
              },
              {
                "id": "wel_b",
                "uw_w_m2k": 0.8,
                "findings": [],
                "edges": [
                  {
                    "side": "top",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  },
                  {
                    "side": "right",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  },
                  {
                    "side": "bottom",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  },
                  {
                    "side": "left",
                    "length_m": 0.5,
                    "install": {
                      "source": "shared",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  }
                ]
              },
              {
                "id": "wel_c",
                "uw_w_m2k": null,
                "findings": [],
                "edges": [
                  {
                    "side": "top",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  },
                  {
                    "side": "right",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  },
                  {
                    "side": "bottom",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  },
                  {
                    "side": "left",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  }
                ]
              }
            ]
          }
        }
      },
      {
        "id": "wnt_single",
        "values": {
          "name": "Single opening",
          "notes": "",
          "rows_m": [
            1.5
          ],
          "columns_m": [
            1
          ],
          "elements": [
            {
              "id": "wel_single",
              "name": "Element 1",
              "kind": "glazed",
              "row_span": [
                0,
                0
              ],
              "column_span": [
                0,
                0
              ],
              "glazing_id": "glz_a",
              "frames": {
                "top": "frm_a",
                "right": "frm_a",
                "bottom": "frm_a",
                "left": "frm_a"
              },
              "installs": {
                "top": null,
                "right": null,
                "bottom": null,
                "left": null
              },
              "operation": {
                "type": "fixed",
                "directions": []
              }
            }
          ]
        },
        "user_data": {},
        "extension_data": {},
        "findings": [],
        "display": {
          "width_m": 1.5,
          "height_m": 1.5,
          "install_depth_m": 0.1,
          "thermal": {
            "uw_w_m2k": 0.8,
            "u_effective_w_m2k": 0.9,
            "complete": true,
            "area_m2": 1.5,
            "empty_area_m2": 0.75,
            "findings": [],
            "elements": [
              {
                "id": "wel_single",
                "uw_w_m2k": 0.8,
                "findings": [],
                "edges": [
                  {
                    "side": "top",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  },
                  {
                    "side": "right",
                    "length_m": 0.5,
                    "install": {
                      "source": "shared",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  },
                  {
                    "side": "bottom",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  },
                  {
                    "side": "left",
                    "length_m": 0.5,
                    "install": {
                      "source": "default",
                      "id": null,
                      "psi_w_mk": 0.04
                    }
                  }
                ]
              }
            ]
          }
        }
      },
      {
        "id": "wnt_two",
        "values": {
          "name": "Two elements",
          "notes": "",
          "rows_m": [
            1.5
          ],
          "columns_m": [
            0.7,
            null
          ],
          "elements": [
            {
              "id": "wel_two0",
              "name": "Element 1",
              "kind": "glazed",
              "row_span": [
                0,
                0
              ],
              "column_span": [
                0,
                0
              ],
              "glazing_id": "glz_a",
              "frames": {
                "top": "frm_a",
                "right": "frm_a",
                "bottom": "frm_a",
                "left": "frm_a"
              },
              "installs": {
                "top": null,
                "right": null,
                "bottom": null,
                "left": null
              },
              "operation": {
                "type": "fixed",
                "directions": []
              }
            },
            {
              "id": "wel_two1",
              "name": "Element 2",
              "kind": "glazed",
              "row_span": [
                0,
                0
              ],
              "column_span": [
                1,
                1
              ],
              "glazing_id": "glz_a",
              "frames": {
                "top": "frm_a",
                "right": "frm_a",
                "bottom": "frm_a",
                "left": "frm_a"
              },
              "installs": {
                "top": null,
                "right": null,
                "bottom": null,
                "left": null
              },
              "operation": {
                "type": "fixed",
                "directions": []
              }
            }
          ]
        },
        "user_data": {},
        "extension_data": {},
        "findings": [],
        "display": {
          "width_m": 1.5,
          "height_m": 1.5,
          "install_depth_m": 0.1,
          "thermal": {
            "uw_w_m2k": null,
            "u_effective_w_m2k": null,
            "elements": [],
            "findings": [
              { "code": "window_type.dimensions_incomplete", "message": "Enter all grid dimensions." }
            ]
          }
        }
      }
    ],
    "unreadable": []
  },
  "frames": {
    "records": [
      {
        "id": "frm_a",
        "values": {
          "name": "Timber frame",
          "manufacturer": "Synthetic",
          "brand": "Line A",
          "notes": "",
          "color": "#eeeeee",
          "width_m": 0.08,
          "uf_w_m2k": 1.1,
          "psi_g_w_mk": 0.03
        },
        "user_data": {},
        "extension_data": {},
        "findings": []
      }
    ]
  },
  "glazings": {
    "records": [
      {
        "id": "glz_a",
        "values": {
          "name": "Triple glazing",
          "manufacturer": "Synthetic",
          "notes": "",
          "color": "#e8f4fa",
          "ug_w_m2k": 0.6,
          "g_value": 0.5
        },
        "user_data": {},
        "extension_data": {},
        "findings": []
      }
    ]
  },
  "psi_install_types": {
    "records": [
      {
        "id": "psi_a",
        "values": {
          "name": "Insulated junction",
          "notes": "",
          "psi_w_mk": 0.04
        },
        "user_data": {},
        "extension_data": {},
        "findings": []
      }
    ]
  },
  "settings": {
    "default_psi_install_id": "psi_a",
    "default_psi_install_w_mk": 0.04,
    "default_install_depth_m": 0.1
  }
};

  FIXTURES.windows.zones = JSON.parse(JSON.stringify(AUTHORING.zones));
  FIXTURES.windows.faces = JSON.parse(JSON.stringify(AUTHORING.faces));
  FIXTURES.windows.windows.units = { units: [
    { id: "wun_a", reference: { unit_id: "wun_a", entity_path: [100, 300] }, name: "",
      values: { window_type_id: "wnt_a", anchor: "sill_center" },
      host: JSON.parse(JSON.stringify(AUTHORING.faces[0].reference)),
      findings: [{ code: "window.definition_detached", repair: { name: "ph_composer.windows.units.reset_to_type",
        params: { units: [{ unit_id: "wun_a", entity_path: [100, 300] }] } } }] },
    { id: "wun_a", reference: { unit_id: "wun_a", entity_path: [100, 301] }, name: "",
      values: { window_type_id: "wnt_a", anchor: "head_right" }, host: null,
      findings: [{ code: "window.copy_id_pending", repair: { name: "ph_composer.windows.units.repair_copied_identities",
        params: { units: [{ unit_id: "wun_a", entity_path: [100, 301] }] } } },
        { code: "window.unhosted", repair: { name: "ph_composer.windows.units.rehost",
        params: { unit: { unit_id: "wun_a", entity_path: [100, 301] } } } }] },
    { id: "wun_c", reference: { unit_id: "wun_c", entity_path: [200, 302] }, name: "W-101",
      values: { window_type_id: "wnt_a", anchor: "sill_left" },
      host: JSON.parse(JSON.stringify(AUTHORING.faces[4].reference)),
      findings: [{ code: "window.mirrored", repair: { name: "ph_composer.windows.units.new_flipped_type",
        params: { unit: { unit_id: "wun_c", entity_path: [200, 302] } } } }] }
  ] };

  FIXTURES.windows.windows.unit_areas = { faces: AUTHORING.faces.map(function (face) {
    var hosted = FIXTURES.windows.windows.units.units.filter(function (unit) {
      return unit.host && JSON.stringify(unit.host) === JSON.stringify(face.reference);
    }), uncertain = hosted.some(function (unit) { return unit.findings.length > 0; });
    return { reference: JSON.parse(JSON.stringify(face.reference)), gross_area_m2: face.area_m2,
      glazed_area_m2: uncertain ? null : 0, net_opaque_area_m2: uncertain ? null : face.area_m2,
      unit_count: hosted.length, findings: uncertain ? ["window.geometry_differs"] : [] };
  }), unhosted_units: [FIXTURES.windows.windows.units.units[1].reference] };

  FIXTURES.windows.libraryProviders = [{ id: "window_products", provider_kind: "ph_composer.library.file",
    label: "Synthetic Window products", kinds: ["frames", "glazings", "psi_install_types"] }];
  FIXTURES.windows.libraryCatalogs = { window_products: ["frames", "glazings", "psi_install_types"].map(
    function (kind) {
      var values = JSON.parse(JSON.stringify(FIXTURES.windows.windows[kind].records[0].values));
      values.name = "Library " + values.name;
      return { kind: kind, library_id: "synthetic.windows", library_name: "Synthetic Window products",
        record_id: kind + "_library", wire_schema_version: 1, snapshot: values };
    }) };
  // Managed choices are separate from the supported legacy authoring fixture.
  FIXTURES.zoneoptions = JSON.parse(JSON.stringify(FIXTURES.authoring));
  FIXTURES.zoneoptions.zoneOptions = {
    building_segments: [{ id: "bsg_house", schema_version: 1, values: {
      name: "House", colour: "#268589", export_identifier: "segment_house" }, usage: { live: 2, recoverable: 1 } },
      { id: "bsg_annex", schema_version: 1, values: { name: "Annex", colour: "#5588BB",
        export_identifier: "segment_annex" }, usage: { live: 0, recoverable: 0 } }],
    levels: [{ id: "lvl_ground", schema_version: 1, values: { name: "Ground", colour: "#9977AA" },
      usage: { live: 1, recoverable: 1 } },
      { id: "lvl_upper", schema_version: 1, values: { name: "Upper", colour: "#CB7854" },
        usage: { live: 1, recoverable: 0 } }],
    default_segment_id: "bsg_house", adoption: { required: false, sources: [] }
  };
  // The occupancy read: House a single dwelling with no bedrooms entered; Annex switched off, its Zone in an
  // Office Program, with the finding a residential Segment with no Dwelling gives.
  FIXTURES.zoneoptions.occupancy = {
    zones: [],
    building_segments: [
      { id: "bsg_house", name: "House", category: "residential", settings: { single_dwelling: true,
        default_program_id: null, bedrooms: null, occupants: null, equipment_set_id: null }, stored: false,
        single_dwelling: true, dwelling: { name: "House", units: 1, bedrooms: null, occupants: null,
          occupants_rule: false, equipment_set_id: null }, dwelling_count: 1,
        set_points: { heating_c: 20, cooling_c: 25, agree: true },
        single_dwelling_preview: { building_segment_id: "bsg_house", programs: [], dwelling_ids: [],
          equipment_set_ids: [], bedrooms: null, occupants: null }, findings: [] },
      { id: "bsg_annex", name: "Annex", category: "residential", settings: { single_dwelling: false,
        default_program_id: "pgm_office", bedrooms: null, occupants: null, equipment_set_id: null }, stored: true,
        single_dwelling: false, dwelling: null, dwelling_count: 0,
        set_points: { heating_c: 20, cooling_c: 25, agree: true },
        single_dwelling_preview: { building_segment_id: "bsg_annex", programs: [], dwelling_ids: [],
          equipment_set_ids: [], bedrooms: null, occupants: null },
        findings: [{ code: "programs.residential_without_dwelling", severity: "warning",
          message: "Annex is residential and has no Dwelling." }] }],
    choices: { programs: [{ id: "pgm_office", name: "Office" }, { id: "pgm_PHCDEFAULT01",
      name: "Residential default" }], equipment_sets: [{ id: "eqs_PHCDEFAULT01",
      name: "Residential default devices" }], default_program_id: "pgm_PHCDEFAULT01",
      default_equipment_set_id: "eqs_PHCDEFAULT01" }
  };
  FIXTURES.zoneoptions.zones.forEach(function (entry) {
    entry.schema_version = 2;
    entry.values = { name: entry.values.name, ground_depth_mm: entry.values.ground_depth_mm,
      building_segment_id: "bsg_house", level_id: entry.values.level === "Ground" ? "lvl_ground" : "lvl_upper" };
  });
  /* ------------------------------------------------------------ Spaces: the `spaces` section the host reads */

  // One Floor Segment, Volume or Space row as the Spaces read publishes it, with its metrics already summed.
  function spaceSegment(path, area, factor) {
    return { id: "sfs_" + path.join("_"), weighting_band: String(factor), findings: [],
      values: { display_name: "Segment 1", weighting_factor: factor, net_area_factor: 1 },
      reference: { floor_segment_id: "sfs_" + path.join("_"), entity_path: path },
      metrics: { floor_area_m2: area, weighted_area_m2: area * factor, net_area_m2: area, horizontal: true } };
  }
  function spaceVolume(path, number, height, segments) {
    var area = segments.reduce(function (sum, item) { return sum + item.metrics.floor_area_m2; }, 0);
    var weighted = segments.reduce(function (sum, item) { return sum + item.metrics.weighted_area_m2; }, 0);
    return { id: "svl_" + path.join("_"), findings: [], floor_segments: segments, nested: false, open: false,
      protected: true, moved: false, reference: { volume_id: "svl_" + path.join("_"), entity_path: path },
      values: { number: number, display_name: "Volume " + number, avg_ceiling_height_m: height },
      metrics: { floor_area_m2: area, weighted_area_m2: weighted, net_area_m2: area, net_volume_m3: area * height } };
  }
  function spaceRow(path, zoneId, number, name, airflows, volumes) {
    var metrics = { floor_area_m2: 0, weighted_area_m2: 0, net_area_m2: 0, net_volume_m3: 0 }, heighted = 0;
    volumes.forEach(function (item) {
      ["floor_area_m2", "weighted_area_m2", "net_area_m2", "net_volume_m3"].forEach(function (key) {
        metrics[key] += item.metrics[key];
      });
      heighted += item.metrics.floor_area_m2 * item.values.avg_ceiling_height_m;
    });
    metrics.average_height_m = metrics.floor_area_m2 ? heighted / metrics.floor_area_m2 : null;
    return { id: "spc_" + number, state: "found", nested: false, findings: [], airflow_mode: null, airflows: {},
      values: Object.assign({ name: name, number: number }, airflows), volumes: volumes, metrics: metrics,
      reference: { space_id: "spc_" + number, entity_path: path },
      zone: zoneId && { zone_id: zoneId, zone_path: zonePath(zoneId) } };
  }
  var AIRFLOW_KEYS = ["v_sup_m3h", "v_eta_m3h", "v_tran_m3h"];
  function rated(space) {
    return AIRFLOW_KEYS.some(function (key) { return Object.prototype.hasOwnProperty.call(space.values, key); });
  }
  // The section: each Space with its Zone's airflow mode (detailed once any Space in the Zone has a rate, else
  // By Program) and each Zone's sums over its Spaces, as the host computes them.
  function spacesSection(spaces, zoneRecords) {
    spaces.forEach(function (space) {
      var zoneId = space.zone && space.zone.zone_id;
      var members = spaces.filter(function (other) {
        return zoneId ? other.zone && other.zone.zone_id === zoneId : other === space;
      });
      space.airflow_mode = members.some(rated) ? "detailed" : "by_program";
      AIRFLOW_KEYS.forEach(function (key) {
        space.airflows[key] = space.airflow_mode === "detailed" ? space.values[key] || 0 : null;
      });
    });
    var zones = (zoneRecords || AUTHORING.zones).map(function (zone) {
      var own = spaces.filter(function (space) { return space.zone && space.zone.zone_id === zone.id; });
      var mode = own.some(function (space) { return space.airflow_mode === "detailed"; }) ? "detailed" : "by_program";
      var flows = {};
      AIRFLOW_KEYS.forEach(function (key) {
        flows[key] = mode === "detailed" ?
          own.reduce(function (sum, space) { return sum + space.airflows[key]; }, 0) : null;
      });
      function sum(key) { return own.reduce(function (total, space) { return total + space.metrics[key]; }, 0); }
      return { zone_id: zone.id, zone_path: zone.reference.zone_path, name: zone.values.name, space_count: own.length,
        floor_area_m2: sum("floor_area_m2"), weighted_area_m2: sum("weighted_area_m2"),
        net_volume_m3: sum("net_volume_m3"), airflow_mode: mode, airflows: flows };
    });
    return { spaces: spaces, zones: zones, findings: [], units: { area: "m2", height: "m", volume: "m3",
      airflow: "m3/h" } };
  }
  var LIVING = "zon_Aa11Bb22Cc33", ATTIC = "zon_Dd44Ee55Ff66";
  // The synthetic reference model's four Spaces (planning ACCEPTANCE): one Zone with detailed airflows and one By
  // Program.
  var REFERENCE_SPACES = spacesSection([
    spaceRow([100, 501], LIVING, "101", "Living", { v_sup_m3h: 60 },
      [spaceVolume([100, 501, 1], 1, 2.5, [spaceSegment([100, 501, 1, 1], 12, 1)])]),
    spaceRow([100, 502], LIVING, "102", "Bath", { v_eta_m3h: 40 },
      [spaceVolume([100, 502, 1], 1, 2.4, [spaceSegment([100, 502, 1, 1], 4, 1)])]),
    spaceRow([100, 503], LIVING, "103", "Hall", { v_tran_m3h: 20 },
      [spaceVolume([100, 503, 1], 1, 2.5, [spaceSegment([100, 503, 1, 1], 4, 1)]),
        spaceVolume([100, 503, 2], 2, 5, [spaceSegment([100, 503, 2, 1], 2, 0)])]),
    spaceRow([200, 601], ATTIC, "201", "Loft", {},
      [spaceVolume([200, 601, 1], 1, 3, [spaceSegment([200, 601, 1, 1], 12, 1)])])]);
  // 300 Spaces, 150 per Zone, for the unit-switch measurement (units U1-F1).
  var LARGE_SPACES = spacesSection(Array.apply(null, { length: 300 }).map(function (unused, index) {
    var zoneId = index < 150 ? LIVING : ATTIC, root = index < 150 ? 100 : 200, id = 1000 + index;
    return spaceRow([root, id], zoneId, String(index + 1), "Room " + (index + 1),
      index % 3 ? { v_sup_m3h: 20 + index % 7, v_eta_m3h: 18 + index % 5 } : {},
      [spaceVolume([root, id, 1], 1, 2.4 + (index % 4) / 10, [spaceSegment([root, id, 1, 1], 8 + index % 9,
        index % 5 ? 1 : 0.5)])]);
  }));
  FIXTURES.spaces = Object.assign(JSON.parse(JSON.stringify(FIXTURES.authoring)), { spaces: REFERENCE_SPACES });
  // Zones with no Spaces yet, and a Model with nothing at all.
  FIXTURES.spacesnone = Object.assign(JSON.parse(JSON.stringify(FIXTURES.authoring)), { spaces: spacesSection([]) });
  FIXTURES.spacesempty = { parts: [], zones: [], faces: [], spaces: { spaces: [], zones: [], findings: [],
    units: { area: "m2", height: "m", volume: "m3", airflow: "m3/h" } } };
  // Create Space's review as SketchUp's context menu hands it over: two Faces accepted, three left out.
  FIXTURES.spacescreate = Object.assign(JSON.parse(JSON.stringify(FIXTURES.spaces)), { createReview: {
    token: "preview-review", revision: 1, zone: { zone_id: "zon_Aa11Bb22Cc33", zone_path: [100] },
    zones: [{ zone_id: "zon_Aa11Bb22Cc33", zone_path: [100], name: "Living Zone" },
      { zone_id: "zon_Dd44Ee55Ff66", zone_path: [200], name: "Second Floor" }],
    accepted: [[901], [902]], height_m: 2.5, height_source: "last_height",
    left_out: [
      { path: [101], reason: "classified", message: "The Face is one of the Zone's own Faces." },
      { path: [102], reason: "classified", message: "The Face is one of the Zone's own Faces." },
      { path: [903], reason: "shares_edge",
        message: "The Face shares an Edge with an unselected Face; grouping it would split that Face." }] } });
  // Convert to Window Type's review as SketchUp's menus hand it over: two Windows of one size, one of a size an
  // existing Type matches, and two rectangles left out.
  function convertSource(path, column) { return { path: [100, path], row_span: [0, 0], column_span: [column, column],
    digest: "sha256:preview" + path, outline_m: [] }; }
  function convertGroup(index, columns, rows, sources, matches, name) {
    return { host: { zone_id: "zon_Aa11Bb22Cc33", zone_path: [100], entity_path: [101], entity_id: null },
      columns_m: columns, rows_m: rows, layout_index: index, matching_types: matches,
      preselected_type_id: matches.length ? matches[0].id : null, default_name: name, sources: sources };
  }
  FIXTURES.windowsconvert = JSON.parse(JSON.stringify(FIXTURES.windows));
  FIXTURES.windowsconvert.windows.convert_dialog = { token: "preview-convert", revision: 1,
    groups: [convertGroup(0, [1.2], [1.5], [convertSource(901, 0)], [], "Window 1200 x 1500"),
      convertGroup(0, [1.2], [1.5], [convertSource(902, 0)], [], "Window 1200 x 1500"),
      convertGroup(2, [0.5, 0.5, 0.5], [1.5], [convertSource(903, 0), convertSource(904, 1), convertSource(905, 2)],
        [{ id: "wnt_a", name: "Three elements" }], "Window 1500 x 1500")],
    left_out: [
      { paths: [[100, 906]], code: "window.not_rectangle",
        message: "The Face is not a rectangle: it needs four square corners and no hole." },
      { paths: [[100, 907]], code: "window.convert_on_boundary",
        message: "The rectangle touches its host Face's edge. Draw it inset, convert it, then move the Window." }] };
  FIXTURES.spaceslarge = Object.assign(JSON.parse(JSON.stringify(FIXTURES.authoring)), { spaces: LARGE_SPACES });

  /* ------------------------------------------- Whole-app Models: every tab with something to show */

  function copy(value) { return JSON.parse(JSON.stringify(value)); }
  // `rich`: a few of everything, one Model across every tab, for reviewing the app as a whole.
  FIXTURES.rich = copy(FIXTURES.windows);
  FIXTURES.rich.materials = copy(FIXTURES.libraries.materials);
  FIXTURES.rich.assemblies = copy(FIXTURES.builder.assemblies);
  FIXTURES.rich.thermalBridges = copy(FIXTURES.thermalbridges.thermalBridges);
  FIXTURES.rich.spaces = copy(REFERENCE_SPACES);
  FIXTURES.rich.libraryProviders = copy(FIXTURES.windows.libraryProviders)
    .concat(copy(FIXTURES.libraries.libraryProviders));
  FIXTURES.rich.libraryCatalogs = Object.assign(copy(FIXTURES.windows.libraryCatalogs),
    copy(FIXTURES.libraries.libraryCatalogs));
  FIXTURES.rich.librarySetupState = "readable";

  // `dense`: the same Model at project scale, to see how each screen holds up under many records.
  var MATERIAL_NAMES = ["Mineral wool", "Wood fibre board", "EPS", "XPS", "Polyiso", "Cellulose", "Concrete",
    "Brick", "CLT", "Gypsum board", "OSB", "Plywood", "Steel", "Aluminium", "Air gap", "Stone wool batt",
    "Cork", "Hemp-lime", "Lime plaster", "Cement board"];
  var MATERIAL_CATEGORIES = [["insulation", "Insulation", "warm", "#fff2cc"], ["woods", "Woods", "wood", "#c69c6d"],
    ["masonry", "Masonry", "stone", "#d7ccc8"], ["metals", "Metals", "cool", "#b0bec5"],
    ["boards", "Boards", "neutral", "#e0e0e0"]];
  function buildDense() {
    var dense = copy(FIXTURES.rich), template = dense.materials.records[0];
    dense.materials.categories = MATERIAL_CATEGORIES.map(function (entry) {
      return { id: entry[0], label: entry[1], tone: entry[2] };
    });
    dense.materials.records = Array.apply(null, { length: 48 }).map(function (unused, index) {
      var record = copy(template), category = MATERIAL_CATEGORIES[index % MATERIAL_CATEGORIES.length];
      record.id = index < 2 ? ["mat_a", "mat_b"][index] : "mat_" + (100 + index);
      record.values.name = MATERIAL_NAMES[index % MATERIAL_NAMES.length] +
        (index >= MATERIAL_NAMES.length ? " " + (Math.floor(index / MATERIAL_NAMES.length) + 1) : "");
      record.values.category = category[0];
      record.values.color = category[3];
      record.values.conductivity_w_mk = Math.round((0.03 + (index % 9) * 0.07) * 1000) / 1000;
      record.values.density_kg_m3 = 20 + (index % 11) * 85;
      record.values.notes = index % 4 ? "" : "Datasheet value, " + (2019 + index % 6);
      record.uses = []; record.use_count = index % 3;
      return record;
    });
    var assembly = dense.assemblies.records;
    var ASSEMBLY_NAMES = ["Exterior wall", "Party wall", "Roof", "Ground floor slab", "Basement wall",
      "Interior floor", "Parapet", "Exposed floor"];
    var ASSEMBLY_TYPES = ["Wall", "Wall", "RoofCeiling", "Floor", "Wall", "Floor", "Wall", "Floor"];
    var COLORS = ["#c5e1a5", "#bbdefb", "#ffe0b2", "#d1c4e9", "#b2dfdb", "#f8bbd0", "#e6ee9c", "#cfd8dc"];
    dense.assemblies.records = Array.apply(null, { length: 32 }).map(function (unused, index) {
      var record = copy(assembly[index % 2]);
      record.id = index < 2 ? ["asm_a", "asm_b"][index] : "asm_" + (100 + index);
      record.values.name = ASSEMBLY_NAMES[index % 8] + " " + String.fromCharCode(65 + Math.floor(index / 8)) +
        (index % 5 === 3 ? " with a long descriptive name for the service cavity" : "");
      record.values.type = ASSEMBLY_TYPES[index % 8];
      record.values.color = COLORS[index % 8];
      record.values.notes = index % 3 ? "" : "Per architect's set, rev " + (index % 4 + 1);
      return record;
    });
    // Twelve Zones over three Levels, eight Faces each, a mix of states.
    var LEVELS = ["Ground", "Level 2", "Level 3"];
    var FACE_STATES = [["Wall", "Outdoors"], ["Wall", "Outdoors"], ["Wall", "Surface"], ["Floor", "Ground"],
      ["RoofCeiling", "Outdoors"], ["Wall", null], [null, null], ["Wall", "Adiabatic"]];
    dense.zones = []; dense.faces = [];
    for (var z = 0; z < 12; z += 1) {
      var zoneId = "zon_D" + String(z).padStart(2, "0") + "ense00000";
      var root = 1000 + z * 100;
      dense.zones.push({ id: zoneId, schema_version: 1, user_data: {}, extension_data: {},
        reference: { zone_id: zoneId, zone_path: [root] }, state: "found", face_count: 8,
        values: { name: "Unit " + (z + 1) + (z % 4 === 0 ? " (corner)" : ""),
          building_segment: z < 8 ? "Block A" : "Block B",
          level: LEVELS[z % 3], ground_depth_mm: z % 3 ? 0 : 450 } });
      FACE_STATES.forEach(function (state, index) {
        var path = root + index + 1, classified = state[0] && state[1];
        var values = state[0] ? { id: "fac_D" + path, face_type: state[0] } : {};
        if (state[1]) values.boundary_condition = state[1];
        if (classified && index % 2 === 0) values.assembly_id = "asm_" + (index % 2 ? "b" : "a");
        dense.faces.push({ reference: { zone_id: zoneId, zone_path: [root], entity_path: [path],
          entity_id: state[0] ? "fac_D" + path : null }, zone_name: "", area_m2: 6 + (index * 3.7 + z) % 24,
          values: values, state: classified ? "classified" : state[0] ? "incomplete" : "unclassified",
          suggested: { face_type: "Wall", boundary_condition: "Outdoors" } });
      });
    }
    // Twenty-four Window Types and twenty Thermal Bridge Types.
    var windowTemplate = dense.windows.types.records[0];
    dense.windows.types.records = Array.apply(null, { length: 24 }).map(function (unused, index) {
      var record = copy(windowTemplate);
      record.id = index ? "wnt_" + (100 + index) : "wnt_a";
      record.values.name = ["Casement", "Fixed", "Door", "Slider", "Tilt-turn", "Ribbon"][index % 6] + " W" +
        String(index + 1).padStart(2, "0");
      return record;
    });
    // Keep the referenced products intact, then populate each independent inventory with unused copies.
    dense.attachedZones = dense.attachedZones.concat(Array.apply(null, { length: 23 }).map(function (unused, index) {
      var record = copy(dense.attachedZones[0]);
      record.id = "atz_dense_" + (index + 1);
      record.values.name = ["Garage", "Unheated basement", "Enclosed porch", "Service room"][index % 4] +
        " " + (index + 2);
      record.values.temperature_reduction_factor = Math.round((0.5 + index % 10 * 0.05) * 100) / 100;
      record.uses = []; record.use_count = 0;
      return record;
    }));
    ["frames", "glazings", "psi_install_types"].forEach(function (kind) {
      var records = dense.windows[kind].records;
      dense.windows[kind].records = records.concat(Array.apply(null, { length: 23 }).map(function (unused, index) {
        var record = copy(records[0]);
        record.id = { frames: "frm", glazings: "glz", psi_install_types: "psi" }[kind] + "_dense_" + (index + 1);
        record.values.name = {
          frames: ["Timber frame", "Insulated timber frame", "Composite frame", "Thermally broken frame"],
          glazings: ["Triple glazing", "Solar-control glazing", "Low-iron glazing", "Acoustic glazing"],
          psi_install_types: ["Insulated sill junction", "Recessed jamb", "Head junction", "Door threshold"]
        }[kind][index % 4] + " " + (index + 2);
        if (kind === "frames") {
          record.values.width_m = (70 + index % 7 * 5) / 1000;
          record.values.uf_w_m2k = (80 + index % 9 * 5) / 100;
          record.values.psi_g_w_mk = (25 + index % 6 * 5) / 1000;
        } else if (kind === "glazings") {
          record.values.ug_w_m2k = (50 + index % 7 * 5) / 100;
          record.values.g_value = (35 + index % 6 * 4) / 100;
        } else record.values.psi_w_mk = (15 + index % 8 * 5) / 1000;
        record.uses = []; record.use_count = 0; record.element_use_count = 0;
        return record;
      }));
    });
    var TB_NAMES = ["Parapet", "Slab edge", "Balcony", "Window sill", "Window head", "Foundation",
      "Corner", "Roof eave", "Steel lintel", "Shelf angle"];
    var TB_GROUPS = ["15-Ambient", "16-Perimeter", "17-FS/BC"];
    var TB_COLORS = ["#c8553d", "#6a8eae", "#d9a23b", "#5b8c5a", "#8e6c8a"];
    dense.thermalBridges.types = Array.apply(null, { length: 20 }).map(function (unused, index) {
      var kept = ["tbt_Aa11Bb22Cc33", "tbt_Dd44Ee55Ff66", "tbt_Gg77Hh88Ii99"][index];
      return tbType(kept || "tbt_D" + String(index).padStart(2, "0") + "ense0000", TB_NAMES[index % 10] +
        (index >= 10 ? " (Block B)" : ""),
        index % 7 === 6 ? null : Math.round(((index % 9) * 0.03 - 0.04) * 1000) / 1000,
        TB_GROUPS[index % 3], TB_COLORS[index % 5]);
    });
    // 300 Spaces spread over the dense Model's own twelve Zones.
    dense.spaces = spacesSection(Array.apply(null, { length: 300 }).map(function (unused, index) {
      var zone = dense.zones[index % 12], root = zone.reference.zone_path[0], id = 5000 + index;
      var space = spaceRow([root, id], zone.id, String(101 + index), "Room " + (index + 1),
        index % 3 ? { v_sup_m3h: 20 + index % 7, v_eta_m3h: 18 + index % 5 } : {},
        [spaceVolume([root, id, 1], 1, 2.4 + (index % 4) / 10, [spaceSegment([root, id, 1, 1], 8 + index % 9,
          index % 5 ? 1 : 0.5)])]);
      space.zone.zone_path = [root];
      return space;
    }), dense.zones);
    return dense;
  }
  FIXTURES.dense = buildDense();
  // The Climate tab (P4c-06): a new Model with no site, which SketchUp reports as geolocated, and one with the
  // site and the design temperatures set. Synthetic coordinates.
  FIXTURES.climate = { parts: [], climate: { geolocation: { geolocated: true, latitude_deg: 42.75,
    longitude_deg: -73.8, hours_from_utc: null } } };
  FIXTURES.climateset = { parts: [], climate: {
    site: { latitude_deg: 42.75, longitude_deg: -73.8, elevation_m: 84, climate_zone: 15, hours_from_utc: -5 },
    design: { heating_99_c: -17.2, cooling_1_c: 30.1, design_temperature_source: "ASHRAE 2021, nearest station" } } };

  // The outline map (P4c-07): the site set, with a Phius station attached nearby. Synthetic coordinates.
  FIXTURES.climatestation = { parts: [], climate: { site: FIXTURES.climateset.climate.site,
    station: { name: "Northfield Regional", latitude_deg: 42.82, longitude_deg: -73.62, elevation_m: 90 } } };

  // Climate Data on This Computer and the Phius pane's empty states (P4c-08): synthetic folders, never a licensed
  // dataset's name, location or counts. `climatedata` has a found folder and one not found, and no site;
  // `climateready` adds the site. The chooser hands Add Folder a third folder.
  function climateFolder(id, name, location, stations, states, notRead) {
    var total = notRead.reduce(function (sum, kind) { return sum + kind.count; }, 0);
    return { id: "climate_folder_" + id, name: name, display_location: location, found: true,
      format: stations ? "phius_station_file" : null, station_count: stations, state_count: states,
      files_not_read: notRead, files_not_read_total: total, complete: true };
  }
  var PREVIEW_FOLDERS = [climateFolder("previewaaaaa", "Preview Stations", "~/Climate/Preview Stations", 1007, 51,
    [{ extension: ".xls", count: 1150 }, { extension: ".db", count: 4 }]),
  { id: "climate_folder_previewbbbbb", name: "Custom sets", display_location: "~/Climate/Custom", found: false,
    format: null, station_count: null, state_count: null, files_not_read: null, files_not_read_total: null,
    complete: null }];
  var PREVIEW_CHOOSER = [climateFolder("previewccccc", "Sheets", "Climate Drive/Sheets", 0, 0,
    [{ extension: ".xlsx", count: 12 }])];
  FIXTURES.climate.climate.chooser = PREVIEW_CHOOSER;
  FIXTURES.climatedata = { parts: [], climate: { folders: PREVIEW_FOLDERS, chooser: PREVIEW_CHOOSER } };
  FIXTURES.climateready = { parts: [], climate: { site: FIXTURES.climateset.climate.site,
    folders: PREVIEW_FOLDERS.slice(0, 1), lastDatasetId: PREVIEW_FOLDERS[0].id, chooser: PREVIEW_CHOOSER } };

  // The station picker (P4c-09): 1,007 invented stations in eight invented states around the site, a few hundred
  // km across, so some pass and most fail. `climatepicker` has none attached; `climatereplace` has the nearest
  // attached, with two edited values. Every name and place is made up.
  function previewStations() {
    var states = ["XA", "XB", "XC", "XD", "XE", "XF", "XG", "XH"], rows = [], seed = 7;
    function next() { seed = (seed * 16807) % 2147483647; return seed / 2147483647; }
    for (var i = 0; i < 1007; i += 1) {
      var state = states[i % states.length], name = "Station " + state + " " + (100 + i);
      rows.push({ key: state + "/STATION_" + (100 + i) + "-mon.txt", name: name, state: state,
        latitude_deg: Math.round((42.75 + (next() - 0.5) * 6) * 1000) / 1000,
        longitude_deg: Math.round((-73.8 + (next() - 0.5) * 8) * 1000) / 1000,
        elevation_m: Math.round(next() * 600) });
    }
    return rows;
  }
  var PREVIEW_STATIONS = previewStations();
  FIXTURES.climatepicker = { parts: [], climate: { site: FIXTURES.climateset.climate.site,
    folders: [PREVIEW_FOLDERS[0], climateFolder("previewddddd", "Invented Second Station Set With a Long Name",
      "~/Climate/Second Set", 1007, 8, [])],
    lastDatasetId: PREVIEW_FOLDERS[0].id, stations: PREVIEW_STATIONS } };
  FIXTURES.climatereplace = { parts: [], climate: Object.assign({}, FIXTURES.climatepicker.climate, {
    station: PREVIEW_STATIONS.slice().sort(function (a, b) {
      return Math.hypot(a.latitude_deg - 42.75, a.longitude_deg + 73.8) -
        Math.hypot(b.latitude_deg - 42.75, b.longitude_deg + 73.8);
    })[0], edited: 2 }) };
  // The attached pane (P4c-10): the nearest station within the elevation limit attached, with the design
  // temperatures set; its file changed since (board 17); on a computer with no climate data folder (board 6); the
  // same station 400 m higher, outside the limits (19). `climatereplace` is the edited station of board 15.
  var NEAREST = PREVIEW_STATIONS.filter(function (row) { return Math.abs(row.elevation_m - 84) <= 100; })
    .sort(function (a, b) {
      return Math.hypot(a.latitude_deg - 42.75, a.longitude_deg + 73.8) -
        Math.hypot(b.latitude_deg - 42.75, b.longitude_deg + 73.8);
    })[0];
  function attachedFixture(changes) {
    return { parts: [], climate: Object.assign({}, FIXTURES.climatepicker.climate,
      { design: FIXTURES.climateset.climate.design, station: NEAREST, edited: 0 }, changes) };
  }
  FIXTURES.climateattached = attachedFixture({});
  FIXTURES.climatechanged = attachedFixture({ source: "changed" });
  FIXTURES.climateother = attachedFixture({ folders: [], lastDatasetId: null });
  FIXTURES.climatefail = attachedFixture({ station: Object.assign({}, NEAREST, { elevation_m: NEAREST.elevation_m +
    400 }) });

  /* ------------------------------------------------------------ Programs: the Zones / Programs view (P4a-09) */

  // The occupancy read (ph_composer.programs.zones) over three Segments, in the shapes Ruby declares: House a
  // single dwelling with no bedrooms entered yet (prototype journey 1); Apartments switched off with two apartments
  // and a corridor in no Dwelling (journeys 2 and 3); School non-residential, its Classroom unassigned and flagged
  // (journey 4). A library file offers Phius multifamily Programs (journey 3). The preview host answers the
  // Programs writes over it (host.js `programsAction`); the derived loads are illustrative.
  function programZone(id, name, segment, path) {
    return { id: id, schema_version: 3, user_data: {}, extension_data: {}, reference: { zone_id: id,
      zone_path: [path] }, state: "found", face_count: 0, face_area_m2: 0, unclassified_face_area_m2: 0,
      values: { name: name, building_segment_id: segment, level_id: null, ground_depth_mm: 0 } };
  }
  function occupancyZone(id, name, segment, path, area, values) {
    return Object.assign({ zone_id: id, reference: { zone_id: id, zone_path: [path] }, name: name,
      building_segment_id: segment, assignment: { program_id: null, dwelling_id: null, equipment_set_id: null,
        bedrooms: null, occupants: null }, program_id: "pgm_PHCDEFAULT01", program_name: "Residential default",
      dwelling_id: null, dwelling_name: null, single_dwelling: false, dwelling_units: null, equipment_set_id: null,
      floor_area_m2: area, icfa_m2: area * 0.9, people: null, lighting_w: null, ventilation_m3h: null,
      ventilation_source: "by_program", missing: {}, findings: [] }, values);
  }
  function occupancySegment(id, name, category, single, values) {
    return Object.assign({ id: id, name: name, category: category, settings: { single_dwelling: single,
      default_program_id: null, bedrooms: null, occupants: null, equipment_set_id: null }, stored: !single,
      single_dwelling: single, dwelling: null, dwelling_count: 0, set_points: { heating_c: 20, cooling_c: 25,
        agree: true }, single_dwelling_preview: { building_segment_id: id, programs: [], dwelling_ids: [],
        equipment_set_ids: [], bedrooms: null, occupants: null }, findings: [],
      sums: { bedrooms: null, occupants: null, floor_area_m2: 0, icfa_m2: 0, people: null, lighting_w: null,
        ventilation_m3h: null, incomplete: [] } }, values);
  }
  var NO_BEDROOMS = "Enter the bedrooms of House: the Phius rule counts occupants from them.";
  // What Ruby says of a Zone with the residential default in no Dwelling (features/programs/missing_values.rb).
  function noDwelling(name) {
    var people = name + " is in no Dwelling, so the Phius occupancy rule has no occupants.";
    return { people: people, lighting_w: name + " is in no Dwelling, so the Phius lighting rule has no units.",
      ventilation_m3h: "Ventilation per person waits for the people. " + people };
  }
  /* The Programs tab's three catalogs (P4a-11), as `programs.all`, `schedules.all` and `equipment_sets.all` answer
     them (features/programs/inventory.rb): the residential default and its Schedules, the Phius office copied from
     a library, an empty lab Program missing every value, and the two Equipment Sets the occupancy read names. */
  function programLoads(changes) {
    var loads = {
      people: { rule: null, people_per_area: null, occupancy_schedule_id: null, activity_schedule_id: null,
        radiant_fraction: 0.3, latent_fraction: null },
      lighting: { rule: null, watts_per_area: null, high_efficacy_fraction: 1, schedule_id: null,
        return_air_fraction: 0, radiant_fraction: 0.32, visible_fraction: 0.25 },
      electric_equipment: { watts_per_area: null, schedule_id: null, radiant_fraction: 0, latent_fraction: 0,
        lost_fraction: 0 },
      gas_equipment: { watts_per_area: null, schedule_id: null, radiant_fraction: 0, latent_fraction: 0,
        lost_fraction: 0 },
      service_hot_water: { rule: null, flow_per_area: null, target_temperature_c: 60, schedule_id: null,
        sensible_fraction: 0.2, latent_fraction: 0.05 },
      infiltration: { flow_per_exterior_area: null, schedule_id: null },
      ventilation: { flow_per_person: null, flow_per_area: null, flow_per_zone: null, air_changes_per_hour: null,
        schedule_id: null },
      setpoint: { heating_c: null, cooling_c: null, heating_schedule_id: null, cooling_schedule_id: null,
        dehumidify_rh: null, humidify_rh: null }
    };
    Object.keys(changes || {}).forEach(function (key) { Object.assign(loads[key], changes[key]); });
    return loads;
  }
  function catalogRow(kind, id, name, values, extra) {
    return Object.assign({ kind: "ph_composer.programs." + kind, id: id, schema_version: 1, user_data: {},
      extension_status: {}, stored: true, values: Object.assign({ name: name, notes: "", datasheet_links: [],
        source: { kind: "manual" } }, values) }, extra);
  }
  function scheduleRow(id, name, values, uses) {
    return catalogRow("schedule", id, name, Object.assign({ days_per_week: 7, weeks_per_year: 52 }, values),
      // The preview host draws each profile from these values (host.js `scheduleProfile`).
      { uses: uses || [], use_count: (uses || []).length, profile: null });
  }
  var DEFAULT_SOURCE = { kind: "ph_composer_default" };
  var PROGRAM_CATALOG = {
    programs: [
      catalogRow("program", "pgm_PHCDEFAULT01", "Residential default", Object.assign({ source: DEFAULT_SOURCE },
        programLoads({ people: { rule: "phius_residential", occupancy_schedule_id: "sch_PHCDEFAULT01",
          activity_schedule_id: "sch_PHCDEFAULT02" }, lighting: { rule: "phius_interior",
          schedule_id: "sch_PHCDEFAULT03" }, electric_equipment: { watts_per_area: 0, schedule_id: "sch_PHCDEFAULT05" },
        gas_equipment: { watts_per_area: 0, schedule_id: "sch_PHCDEFAULT05" }, service_hot_water: {
          rule: "building_america", target_temperature_c: 43.3, schedule_id: "sch_PHCDEFAULT04" },
        infiltration: { flow_per_exterior_area: 0.0003, schedule_id: "sch_PHCDEFAULT05" }, ventilation: {
          flow_per_person: 0, flow_per_area: 0, flow_per_zone: 0, air_changes_per_hour: 0.4,
          schedule_id: "sch_PHCDEFAULT06" }, setpoint: { heating_c: 20, cooling_c: 25, dehumidify_rh: 60 } })),
      { stored: false, default: true, use_count: 6, missing: [] }),
      catalogRow("program", "pgm_office", "Phius NR Office", Object.assign({ source: { kind: "library",
        library_id: "phius.nonresidential", record_id: "office", library_name: "Phius Non-Residential" } },
        programLoads({ people: { people_per_area: 0.0538, occupancy_schedule_id: "sch_office" },
          lighting: { watts_per_area: 7.64, schedule_id: "sch_office" }, electric_equipment: { watts_per_area: 15,
            schedule_id: "sch_office" }, gas_equipment: { watts_per_area: 0 },
          service_hot_water: { flow_per_area: 0.03 },
          infiltration: { flow_per_exterior_area: 0.0003 }, ventilation: { flow_per_person: 0.0025,
            flow_per_area: 0.0003, schedule_id: "sch_PHCDEFAULT06", source: "2019::MediumOffice::OpenOffice" },
          setpoint: { heating_c: 21.1, cooling_c: 23.9 } })),
      { default: false, use_count: 1, missing: [] }),
      catalogRow("program", "pgm_lab", "Wet lab", programLoads({}), { default: false, use_count: 0, missing: [
        { load: "people", field: "people_per_area" }, { load: "lighting", field: "watts_per_area" },
        { load: "electric_equipment", field: "watts_per_area" }, { load: "gas_equipment", field: "watts_per_area" },
        { load: "service_hot_water", field: "flow_per_area" },
        { load: "infiltration", field: "flow_per_exterior_area" },
        { load: "ventilation", field: "flow_per_person" }, { load: "setpoint", field: "heating_c" },
        { load: "setpoint", field: "cooling_c" }] })
    ],
    schedules: [
      scheduleRow("sch_PHCDEFAULT01", "Residential occupancy", { source: DEFAULT_SOURCE, type: "fractional",
        start_h: 0, end_h: 24, fraction_on: 0.72, fraction_off: 0 }, [{ program_id: "pgm_PHCDEFAULT01",
        name: "Residential default", slot: "people.occupancy_schedule_id" }]),
      scheduleRow("sch_PHCDEFAULT02", "Residential activity", { source: DEFAULT_SOURCE, type: "activity",
        start_h: 0, end_h: 24, watts_on: 112.5, watts_off: 112.5 }, [{ program_id: "pgm_PHCDEFAULT01",
        name: "Residential default", slot: "people.activity_schedule_id" }]),
      scheduleRow("sch_PHCDEFAULT03", "Residential lighting", { source: DEFAULT_SOURCE, type: "fractional",
        start_h: 0, end_h: 24, fraction_on: 0.04, fraction_off: 0 }),
      scheduleRow("sch_PHCDEFAULT04", "Residential hot water", { source: DEFAULT_SOURCE, type: "fractional",
        start_h: 0, end_h: 24, fraction_on: 0.04, fraction_off: 0 }),
      scheduleRow("sch_PHCDEFAULT05", "Always on", { source: DEFAULT_SOURCE, type: "fractional", start_h: 0,
        end_h: 24, fraction_on: 1, fraction_off: 0 }),
      scheduleRow("sch_PHCDEFAULT06", "Constant ventilation", { source: DEFAULT_SOURCE, type: "ventilation",
        periods: [{ period: "high", hours: 0, fraction: 1 }, { period: "standard", hours: 24, fraction: 1 },
          { period: "basic", hours: 0, fraction: 0.5 }, { period: "minimum", hours: 0, fraction: 0.3 }] }),
      scheduleRow("sch_heating", "Heating setback", { type: "temperature", value_c: 20 }),
      scheduleRow("sch_office", "Office hours", { type: "fractional", start_h: 7, end_h: 19, fraction_on: 0.8,
        fraction_off: 0, days_per_week: 5 }, [{ program_id: "pgm_office", name: "Phius NR Office",
        slot: "people.occupancy_schedule_id" }])
    ],
    equipment_sets: [
      // Devices as features/programs/equipment_types.rb stores them: every field its type carries.
      catalogRow("equipment_set", "eqs_PHCDEFAULT01", "Phius single-family", { source: DEFAULT_SOURCE, devices: [
        { id: "dev_PHCDEFAULT01", type: "fridge_freezer", display_name: "Fridge-freezer", quantity: 1,
          in_conditioned_space: true, comment: "", reference_quantity: 4, reference_energy_norm: 1, energy_demand: 1,
          energy_demand_per_use: 0 },
        { id: "dev_PHCDEFAULT02", type: "dishwasher", display_name: "Dishwasher", quantity: 1,
          in_conditioned_space: true, comment: "", reference_quantity: 1, reference_energy_norm: 2, energy_demand: 269,
          energy_demand_per_use: 0, capacity_type: 1, capacity_place_settings: 12, water_connection: "cold_water" },
        { id: "dev_PHCDEFAULT04", type: "clothes_dryer", display_name: "Laundry - dryer", quantity: 1,
          in_conditioned_space: true, comment: "", reference_quantity: 1, reference_energy_norm: 2,
          energy_demand_per_use: 0, dryer_type: "electric_exhaust_air", combined_energy_factor: 3.93,
          gas_consumption: 0, gas_efficiency_factor: 2.67, field_utilization_factor_type: 1,
          field_utilization_factor: 1.18 },
        { id: "dev_PHCDEFAULT08", type: "phius_mel", display_name: "Phius MEL", quantity: 1,
          in_conditioned_space: true, comment: "", reference_quantity: 3 }] },
      { stored: false, default: true, use_count: 3 }),
      catalogRow("equipment_set", "eqs_apartment", "Apartment kitchen", { devices: [] },
        { default: false, use_count: 1 })
    ]
  };

  FIXTURES.programs = {
    parts: [],
    programCatalog: PROGRAM_CATALOG,
    zones: [programZone("zon_living", "Living", "bsg_house", 101),
      programZone("zon_bedroom", "Bedroom", "bsg_house", 102),
      programZone("zon_apt1", "Apt 1", "bsg_apartments", 201),
      programZone("zon_apt2", "Apt 2", "bsg_apartments", 202),
      programZone("zon_corridor", "Corridor", "bsg_apartments", 203),
      programZone("zon_classroom", "Classroom", "bsg_school", 301)],
    zoneOptions: { building_segments: [
      { id: "bsg_house", schema_version: 1, values: { name: "House", colour: "#268589",
        export_identifier: "segment_house" }, usage: { live: 2, recoverable: 0 }, extension_data: {} },
      { id: "bsg_apartments", schema_version: 1, values: { name: "Apartments", colour: "#5588BB",
        export_identifier: "segment_apartments" }, usage: { live: 3, recoverable: 0 }, extension_data: {} },
      { id: "bsg_school", schema_version: 1, values: { name: "School", colour: "#CB7854",
        export_identifier: "segment_school" }, usage: { live: 1, recoverable: 0 }, extension_data: {} }],
      levels: [], default_segment_id: "bsg_house", adoption: { required: false, sources: [] } },
    occupancy: {
      zones: [
        occupancyZone("zon_living", "Living", "bsg_house", 101, 30, { single_dwelling: true, dwelling_name: "House",
          dwelling_units: 1, lighting_w: 62, missing: { people: NO_BEDROOMS,
            ventilation_m3h: "Ventilation per person waits for the people. " + NO_BEDROOMS } }),
        occupancyZone("zon_bedroom", "Bedroom", "bsg_house", 102, 14, { single_dwelling: true,
          dwelling_name: "House", dwelling_units: 1, lighting_w: 29, missing: { people: NO_BEDROOMS,
            ventilation_m3h: "Ventilation per person waits for the people. " + NO_BEDROOMS } }),
        occupancyZone("zon_apt1", "Apt 1", "bsg_apartments", 201, 60, { missing: noDwelling("Apt 1") }),
        occupancyZone("zon_apt2", "Apt 2", "bsg_apartments", 202, 55, { missing: noDwelling("Apt 2") }),
        occupancyZone("zon_corridor", "Corridor", "bsg_apartments", 203, 24, { missing: noDwelling("Corridor") }),
        occupancyZone("zon_classroom", "Classroom", "bsg_school", 301, 70, { people: 3.5, lighting_w: 490,
          ventilation_m3h: 420, findings: [{ code: "programs.unassigned_zone", severity: "warning",
            message: "Classroom has no Program of its own or from School." }] })],
      building_segments: [
        occupancySegment("bsg_house", "House", "residential", true, { dwelling: { name: "House", units: 1,
          bedrooms: null, occupants: null, occupants_rule: false, equipment_set_id: null }, dwelling_count: 1,
          sums: { bedrooms: null, occupants: null, floor_area_m2: 44, icfa_m2: 39.6, people: null, lighting_w: 91,
            ventilation_m3h: null, incomplete: ["people", "ventilation_m3h"] } }),
        occupancySegment("bsg_apartments", "Apartments", "residential", false, {
          findings: [{ code: "programs.residential_without_dwelling", severity: "warning",
            message: "Apartments is residential and has no Dwelling." }],
          sums: { bedrooms: null, occupants: null, floor_area_m2: 139, icfa_m2: 125.1, people: null,
            lighting_w: null, ventilation_m3h: null, incomplete: ["people", "lighting_w", "ventilation_m3h"] } }),
        occupancySegment("bsg_school", "School", "non_residential", false, {
          findings: [{ code: "programs.unassigned_zone", severity: "warning",
            message: "Classroom has no Program of its own or from School." }],
          sums: { bedrooms: null, occupants: null, floor_area_m2: 70, icfa_m2: 63, people: 3.5, lighting_w: 490,
            ventilation_m3h: 420, incomplete: [] } })],
      // The read lists a single dwelling's house among the Dwellings, with a null id.
      dwellings: [{ id: null, name: "House", units: 1, single_dwelling: true, own_bedrooms: null, own_occupants: null,
        bedrooms: null, occupants: null, occupants_rule: false, equipment_set_id: null,
        zone_ids: ["zon_living", "zon_bedroom"], building_segment_ids: ["bsg_house"], floor_area_m2: 44,
        icfa_m2: 39.6, findings: [] }],
      choices: { programs: [{ id: "pgm_office", name: "Phius NR Office" },
        { id: "pgm_PHCDEFAULT01", name: "Residential default" }],
        equipment_sets: [{ id: "eqs_PHCDEFAULT01", name: "Phius single-family" },
          { id: "eqs_apartment", name: "Apartment kitchen" }],
        default_program_id: "pgm_PHCDEFAULT01", default_equipment_set_id: "eqs_PHCDEFAULT01" }
    },
    libraryProviders: [{ id: "phius_mf", provider_kind: "ph_composer.library.file", label: "Phius Multifamily",
      kinds: ["programs", "schedules"] }],
    libraryCatalogs: { phius_mf: [
      { kind: "schedules", library_id: "phius.multifamily", library_name: "Phius Multifamily",
        record_id: "corridor-hours", wire_schema_version: 1, snapshot: { name: "Corridor hours" } },
      { kind: "programs", library_id: "phius.multifamily", library_name: "Phius Multifamily",
        record_id: "corridor", wire_schema_version: 1, snapshot: { name: "Phius MF Corridor" } },
      { kind: "programs", library_id: "phius.multifamily", library_name: "Phius Multifamily",
        record_id: "lobby", wire_schema_version: 1, snapshot: { name: "Phius MF Lobby" } }] }
  };

  global.PhComposerPreviewFixtures = {
    names: Object.keys(FIXTURES),
    // The Spaces section summed again after the preview host writes rates, by the same rule as the fixtures.
    spacesSection: spacesSection,
    fromQuery: function (search) {
      var match = /[?&]fixture=([a-z]+)/.exec(search || "");
      return FIXTURES[match && FIXTURES[match[1]] ? match[1] : "parts"];
    }
  };
}(typeof window !== "undefined" ? window : this));
