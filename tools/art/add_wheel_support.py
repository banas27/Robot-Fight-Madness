"""Add chassis-mounted supports to the saved robot sources and export new revisions."""
import argparse
import json
from math import pi
from pathlib import Path
import sys

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_robot import export_robot

PROJECT = Path(__file__).resolve().parents[2]
REVISIONS = {"riptide": ("saw", "v03"), "bulldozer": ("drum", "v04")}


def blender_point(x, y, z):
    return x, -z, y


def finish(chassis, name, material, bevel):
    part = bpy.context.object
    part.name = name
    part.parent = chassis
    collection = chassis.users_collection[0]
    if collection not in part.users_collection:
        collection.objects.link(part)
    for previous in list(part.users_collection):
        if previous != collection:
            previous.objects.unlink(part)
    part.data.materials.append(material)
    edge = part.modifiers.new("Machined edges", "BEVEL")
    edge.width = bevel
    edge.segments = 1
    edge.affect = "EDGES"
    edge.harden_normals = True


def block(chassis, name, center, size, material, bevel=0.010):
    bpy.ops.mesh.primitive_cube_add(size=1, location=blender_point(*center))
    bpy.context.object.dimensions = size[0], size[2], size[1]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish(chassis, name, material, bevel)


def shaft(chassis, name, center, radius, depth, material, sides=16):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=sides, radius=radius, depth=depth,
        location=blender_point(*center), rotation=(0, pi / 2, 0),
    )
    finish(chassis, name, material, 0.003)


def build(robot):
    kind, version = REVISIONS[robot]
    contract = json.loads((PROJECT / "config/wheel_support.json").read_text())[kind]
    root = bpy.data.objects[f"Robot_{robot.title()}"]
    chassis = bpy.data.objects["Chassis"]
    graphite = bpy.data.materials["Frame_Graphite"]
    steel = bpy.data.materials["Weapon_Steel"]
    amber = bpy.data.materials["Safety_Amber"]
    for obj in list(chassis.children):
        if obj.name.endswith(" stationary axle"):
            bpy.data.objects.remove(obj, do_unlink=True)

    skid_x, skid_y, skid_z = contract["skid_center"]
    bearing_x, bearing_y = contract["bearing_center"]
    axle_x = contract["shaft_center"]
    axle_length = contract["shaft_length"]
    for side in (-1, 1):
        label = "Left" if side < 0 else "Right"
        block(chassis, f"{label} belly skid", (side * skid_x, skid_y, skid_z), contract["skid_size"], steel, 0.012)
    for end in ("F", "R"):
        axle = bpy.data.objects[f"Wheel_{end}L"]
        _, fore, axle_y = axle.location
        axle_z = -fore
        block(chassis, f"{end} underside crossmember", (0, -0.143, axle_z), (2 * skid_x, 0.112, 0.155), graphite)
        for side, label in ((-1, "L"), (1, "R")):
            key = end + label
            block(chassis, f"{key} bearing carrier", (side * bearing_x, bearing_y, axle_z), contract["bearing_size"], graphite)
            face = bearing_x + contract["bearing_size"][0] * 0.5
            shaft(chassis, f"{key} bearing collar", (side * (face - 0.013), axle_y, axle_z), 0.087, 0.032, amber)
            shaft(chassis, f"{key} fixed stub axle", (side * axle_x, axle_y, axle_z), 0.055, axle_length, steel)
            tip = axle_x + axle_length * 0.5 - 0.010
            shaft(chassis, f"{key} axle key", (side * tip, axle_y, axle_z), 0.041, 0.024, graphite, 6)

    root["asset_version"] = version
    chassis["retained_after_wheel_loss"] = "Bearing carriers, stub axles, crossmembers and skids"
    bpy.context.preferences.filepaths.save_version = 0
    source = PROJECT / f"art/source/robots/{robot}/{robot}_{version}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    export_robot(root, PROJECT / f"assets/robots/{robot}/{robot}_{version}.glb")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--robot", choices=REVISIONS, required=True)
    build(parser.parse_args(sys.argv[sys.argv.index("--") + 1:]).robot)
