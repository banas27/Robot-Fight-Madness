"""Build Bulldozer's tracked review variant from the saved v04 Blender source."""
import json
from math import cos, pi, sin, tau
from pathlib import Path
import sys

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from add_wheel_support import blender_point, block, shaft
from export_robot import export_robot

PROJECT = Path(__file__).resolve().parents[2]
TRACK = json.loads((PROJECT / "config/bulldozer_tracks.json").read_text())


def loop_pose(distance):
    half_run, radius = TRACK["half_run"], TRACK["pitch_radius"]
    straight = 2 * half_run
    arc = pi * radius
    if distance < straight:
        return radius, distance - half_run, 0
    if distance < straight + arc:
        angle = (distance - straight) / radius
        return radius * cos(angle), half_run + radius * sin(angle), angle
    if distance < 2 * straight + arc:
        return -radius, half_run - (distance - straight - arc), pi
    angle = pi + (distance - 2 * straight - arc) / radius
    return radius * cos(angle), -half_run + radius * sin(angle), angle


def pivot(root, collection, name, at):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.parent = root
    obj.location = blender_point(*at)
    obj.empty_display_size = 0.035
    return obj


def road_wheel(wheel, side, radius, drive=False):
    graphite = bpy.data.materials["Frame_Graphite"]
    steel = bpy.data.materials["Weapon_Steel"]
    amber = bpy.data.materials["Safety_Amber"]
    gunmetal = bpy.data.materials["Drum_Gunmetal"]
    shaft(wheel, "Road wheel band", (0, 0, 0), radius, 0.247, graphite, 32)
    shaft(wheel, "Steel sprocket rim", (side * 0.107, 0, 0), radius * 0.86, 0.042, gunmetal, 32)
    shaft(wheel, "Recessed wheel face", (side * 0.129, 0, 0), radius * 0.68, 0.020, graphite, 24)
    shaft(wheel, "Axle flange", (side * 0.143, 0, 0), 0.071, 0.020, steel)
    shaft(wheel, "Captive axle nut", (side * 0.158, 0, 0), 0.041, 0.020, amber, 6)
    for bolt in range(6):
        angle = tau * bolt / 6
        shaft(wheel, "Flange bolt", (side * 0.143, 0.107 * cos(angle), 0.107 * sin(angle)),
              0.013, 0.017, amber if drive else steel, 6)


def build():
    root = bpy.data.objects["Robot_Bulldozer"]
    chassis = bpy.data.objects["Chassis"]
    editable = root.users_collection[0]
    track_collection = bpy.data.collections.new("TRACK_SHOES")
    editable.children.link(track_collection)
    for obj in list(chassis.children):
        if " wheel guard" in obj.name or " guard rub rail" in obj.name:
            bpy.data.objects.remove(obj, do_unlink=True)
    half_run, radius = TRACK["half_run"], TRACK["pitch_radius"]
    x, y = TRACK["center_x"], TRACK["center_y"]
    count = TRACK["links_per_side"]
    pitch = (4 * half_run + tau * radius) / count
    gunmetal = bpy.data.materials["Drum_Gunmetal"]
    graphite = bpy.data.materials["Frame_Graphite"]
    steel = bpy.data.materials["Weapon_Steel"]
    prototype = None
    for side, label in ((-1, "L"), (1, "R")):
        for end, at in (("F", -half_run), ("R", half_run)):
            wheel = bpy.data.objects[f"Wheel_{end}{label}"]
            for detail in list(wheel.children):
                bpy.data.objects.remove(detail, do_unlink=True)
            wheel.location = blender_point(side * x, y, at)
            road_wheel(wheel, side, 0.250, end == "R")
        middle = pivot(root, editable, f"Idler_{label}", (side * x, y - 0.026, 0))
        middle["axis_godot"] = "X"
        road_wheel(middle, side, 0.224)
        shaft(chassis, f"Middle road-wheel shaft {label}", (side * 0.511, y - 0.026, 0), 0.061, 0.124, steel)
        for index in range(count):
            radial_y, z, angle = loop_pose(pitch * index)
            shoe = pivot(root, track_collection, f"TrackLink_{label}{index:02}", (side * x, y + radial_y, z))
            shoe.rotation_euler.x = angle
            if prototype is None:
                block(shoe, "Cast track plate", (0, 0, 0), (0.279, 0.035, pitch * 0.96), gunmetal, 0.006)
                block(shoe, "Traction bar", (0, 0.018, 0), (0.254, 0.016, 0.039), graphite, 0.004)
                for edge in (-1, 1):
                    block(shoe, "Shoe edge", (edge * 0.129, 0.003, 0), (0.028, 0.044, 0.056), steel, 0.004)
                prototype = shoe
            else:
                for part in prototype.children:
                    duplicate = part.copy()
                    track_collection.objects.link(duplicate)
                    duplicate.parent = shoe
                    duplicate.matrix_basis = part.matrix_basis.copy()
    root["asset_version"] = "v05-tracks"
    root["track_layout"] = "Two independent loops, 36 shoes each, three road wheels per side"
    bpy.context.preferences.filepaths.save_version = 0
    source = PROJECT / "art/source/robots/bulldozer/bulldozer_v05_tracks.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    export_robot(root, PROJECT / "assets/robots/bulldozer/bulldozer_v05_tracks.glb")


if __name__ == "__main__":
    build()
