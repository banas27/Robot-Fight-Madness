# Robot roster — art direction v01

The owner selected **stylized industrial**. Riptide v02 and Bulldozer v03 are the first pair for visual review.

## Shared visual language

- Low, credible combat machines with a clearly exposed working weapon. Original designs, not replicas of competition robots.
- Large beveled armor planes, compact mechanical joints and deep panel breaks. A silhouette must read at approximately 80–120 pixels wide in the existing vertical broadcast camera.
- Roughly 60% team color, 25% charcoal structure/rubber, 15% exposed steel and pale identification. Tiny status lights; no glowing body panels.
- Satin powder-coated armor, rough rubber, machined weapon edges. Restrained edge wear; no noisy procedural shaders that disappear on GLB export.
- Four broad visual tiers: body silhouette, weapon, team-color blocks, then fasteners/vents. Fine details serve closeups and must not carry identity.
- Riptide has cyan swept shoulders, a dark service spine and a horizontal steel circular saw. Bulldozer has orange armor, blunt rectangular shoulders, recessed wheels and a spinning spiked drum.

## Scale and axes — match the existing R01

One Blender meter = one Godot unit. This is a **scene convention**, not a claim about real competition weight classes. Keep the current arena and combat tuning.

| Property | Contract |
| --- | --- |
| Godot axes | +Y up, -Z robot forward, +X right |
| Blender axes | +Z up, +Y robot forward, +X right; export glTF with +Y up |
| Root | Existing rigid-body origin, not ground; identity scale and rotation |
| Ground relative to root | Godot Y = -0.40; Blender Z = -0.40 |
| Existing chassis collider | 1.34 × 0.65 × 1.62 units, centered on rigid-body root |
| Riptide chassis | About 1.20 wide × 1.35 long, body top below Y = 0.45 |
| Riptide wheel radius | 0.32; centers X = ±0.73, Y = -0.08, Z = ±0.43 |
| Riptide weapon pivot | (0, 0.04, -0.87) in Godot; rotate local Y |
| Bulldozer wheel radius | 0.295 with centers X = ±0.605, Y = -0.105, Z = ±0.433 |
| Bulldozer weapon pivot | (0, -0.021, -1.125) in Godot. Rotate around local X between the fixed bearing forks. |
| Moving parts | Wheel pivots and Bulldozer's drum rotate about local X. Riptide's saw rotates about local Y. |

R02 fits compound chassis primitives and samples the rotating teeth separately. When a weapon's mesh or pivot changes, check its contact profile in `scripts/combat/weapon_contact.gd` and rerun the clearance and combat checks.

## Asset contract

```text
art/source/robots/<id>/<id>_v01.blend   editable source and studio collection
art/review/<id>/                      stills and review evidence
assets/robots/<id>/<id>_v01.glb        game asset only
assets/robots/<id>/asset.json          version, measured bounds, pivots, budgets
tools/art/                            reproducible build / export utilities
scenes/review/                        optional Godot review scenes
scripts/art/                         visual-only adapters and review controls
qa/art-r01/                           isolated validation, existing QA retained
```

`art/source/.gdignore` excludes Blender sources from Godot's automatic conversion.
Use explicit GLB export; the game must not require an installed Blender or connector.

```text
Robot_Riptide
  Chassis
    ChassisMesh
  Wheel_FL       (pivot at axle center; front = -Z)
    Wheel_FL_Mesh
  Wheel_FR
  Wheel_RL
  Wheel_RR
  WeaponPivot    (pivot at spinner spindle)
    WeaponMesh
```

Source objects stay separately editable under these assemblies. Export joins evaluated meshes **within each assembly only**, preserving six independent assemblies and their pivots. Apply mesh scale, preserve root/pivot identity transforms, export normals and standard metallic/roughness materials. No cameras, lights, colliders, external images or rig dependency in GLB. Naming is stable across revisions.

Initial target: under 25,000 exported triangles, eight or fewer materials, under 5 MB GLB. Use shared materials, merge static details per assembly, avoid textures until the review calls for them. Budget is an upper limit, not a target.

## Proposed ten-robot roster

Only the first two names and combat roles exist in the simulation. The remaining names and mechanisms are art proposals; they do not authorize eight new combat systems.

| # | Robot | Color | Silhouette / weapon identity | Status |
| --- | --- | --- | --- | --- |
| 01 | Riptide | Cyan | Swept low hull with a horizontal front saw | Circular saw revision |
| 02 | Bulldozer | Orange | Broad square hull with recessed wheels and a transverse spiked drum | v03 review model |
| 03 | Anvil | Crimson | Compact armored block; tall vertical flywheel | Proposed |
| 04 | Mantis | Acid green | Narrow split prow; overhead articulated striker | Proposed |
| 05 | Sawtooth | Yellow | Offset deck; raised circular saw arm | Proposed |
| 06 | Viper | Violet | Long pointed wedge; twin lifting forks | Proposed |
| 07 | Bastion | Ivory / navy | Wide shield body; central lifting scoop | Proposed |
| 08 | Scorpion | Copper | Low broad rear; arched overhead puncture arm | Proposed |
| 09 | Cyclone | Magenta | Round central chassis; perimeter spinning ring | Proposed |
| 10 | Frostbite | Ice blue / black | Open U-shaped nose; twin opposing crusher jaws | Proposed |

## Review before roster production

Use the Blender studio renders for the three-quarter and top views. Use the Godot review arena to check weapon clearance, team colors at match distance, and motion around each pivot. The pair establishes the proportions and finish for the rest of the roster. See [Robot art review](REVIEW.md).

## Pipeline references

- [Blender glTF exporter](https://docs.blender.org/manual/en/latest/addons/import_export/scene_gltf2.html): standard PBR export and +Y-up conversion.
- [Godot 3D import](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/index.html): GLB scene import and inherited scenes.

Local tool checks on 2026-11-09: Blender **5.1.2** background Python and glTF exporter work; Godot **4.7.2** runs the original seeded simulation. No dedicated Blender MCP connector is exposed in this chat. No add-on or plugin installation is required.
