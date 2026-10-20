#!/usr/bin/env python3
"""
Converts an OSM GeoJSON export (Overpass Turbo / osmium export) into a single
JSON file that Godot 4 can load easily.

Usage:
    python osm_to_godot.py export.geojson map.json [--origin-utm X Y]

Output coordinates are in METERS, relative to a fixed UTM origin, with Y flipped
(Godot: +Y is down, so north is -Y). Scaling to pixels is done in Godot.

Dependencies:  shapely, pyproj, numpy
    sudo pacman -S python-shapely python-pyproj python-numpy
"""
import argparse
import json

from pyproj import Transformer
from shapely.affinity import affine_transform
from shapely.geometry import LineString, MultiPolygon, Polygon, shape
import numpy as np
import shapely

# SIRGAS 2000 / UTM zone 22S (good for Santa Maria)
TARGET_CRS = "EPSG:31982"

# Pinned world origin in UTM. Never change this: authored positions depend on it.
DEFAULT_ORIGIN_UTM: tuple[float, float] = (228400.0, 6712900.0)

# Road width in meters by highway class (used if there is no usable `width` tag)
ROAD_WIDTHS = {
    "motorway": 14, "trunk": 14, "primary": 12, "secondary": 10,
    "tertiary": 9, "unclassified": 7, "residential": 7, "living_street": 5,
    "service": 4, "track": 3, "pedestrian": 4, "footway": 1.5,
    "path": 1.5, "cycleway": 2, "steps": 1.5,
}
SKIP_HIGHWAY = {"proposed", "construction", "razed", "abandoned", "platform"}

# Tags kept in the output (everything else is dropped to keep the file small)
KEEP_TAGS = {
    "name", "alt_name", "highway", "building", "building:levels",
    "building:material", "height", "oneway", "lanes", "maxspeed", "surface",
    "access", "width", "bridge", "tunnel", "layer", "junction", "landuse",
    "natural", "leisure", "waterway", "amenity", "shop", "railway",
    "roof:material", "roof:colour", "addr:street", "addr:housenumber",
    "addr:postcode",
}


def round_pt(p):
    return [round(p[0], 2), round(p[1], 2)]


def polys_of(geom):
    """Return a list of shapely Polygons from a Polygon/MultiPolygon."""
    if geom.is_empty:
        return []
    if isinstance(geom, Polygon):
        return [geom]
    if isinstance(geom, MultiPolygon):
        return list(geom.geoms)
    return [g for g in getattr(geom, "geoms", []) if isinstance(g, Polygon)]


def poly_to_rings(poly):
    """[outer, hole1, ...] with each ring as [[x, y], ...] (not closed)."""
    rings = [poly.exterior] + list(poly.interiors)
    return [[round_pt(c) for c in list(r.coords)[:-1]] for r in rings]


def parse_width(value):
    try:
        return float(str(value).lower().replace("m", "").strip().replace(",", "."))
    except (ValueError, AttributeError):
        return None


def output_bounds(out):
    """Bounding box [min_x, min_y, max_x, max_y] of every written coordinate."""
    min_x = min_y = float("inf")
    max_x = max_y = float("-inf")
    for key in ("landuse", "waterways", "roads", "buildings"):
        for entry in out[key]:
            for polygon_rings in entry.get("polys", []):
                for ring in polygon_rings:
                    for x, y in ring:
                        min_x = min(min_x, x)
                        min_y = min(min_y, y)
                        max_x = max(max_x, x)
                        max_y = max(max_y, y)
            for x, y in entry.get("line", []):
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if min_x == float("inf"):
        return [0.0, 0.0, 0.0, 0.0]
    return [round(min_x, 2), round(min_y, 2), round(max_x, 2), round(max_y, 2)]


def main(src: str, dst: str, origin_utm: tuple[float, float]) -> None:
    with open(src, encoding="utf-8") as f:
        data = json.load(f)

    to_utm = Transformer.from_crs("EPSG:4326", TARGET_CRS, always_xy=True).transform

    # 1) Project every geometry to meters
    items = []
    for feat in data["features"]:
        props = feat.get("properties", {})
        osm_id = feat.get("id") or props.get("@id") or "unknown"
        geom = shapely.transform(
            shape(feat["geometry"]),
            lambda c: np.column_stack(to_utm(c[:, 0], c[:, 1])),
        )
        items.append((osm_id, props, geom))
    if not items:
        raise SystemExit("Input file contains no features.")

    # 2) Keep the imported extent for meta.size_m (the old semantics)
    minx = min(g.bounds[0] for _, _, g in items)
    miny = min(g.bounds[1] for _, _, g in items)
    maxx = max(g.bounds[2] for _, _, g in items)
    maxy = max(g.bounds[3] for _, _, g in items)

    # 3) Subtract the pinned origin and flip Y.
    origin_x, origin_y = origin_utm
    matrix = [1, 0, 0, -1, -origin_x, origin_y]

    out = {"landuse": [], "waterways": [], "roads": [], "buildings": []}

    for osm_id, props, geom in items:
        geom = affine_transform(geom, matrix)
        tags = {k: v for k, v in props.items() if k in KEEP_TAGS}
        entry = {"id": osm_id, "name": props.get("name", ""), "tags": tags}

        if "highway" in props:
            kind = props["highway"]
            if kind in SKIP_HIGHWAY or not isinstance(geom, LineString):
                continue
            width = parse_width(props.get("width")) or ROAD_WIDTHS.get(kind, 4)
            coords = list(geom.coords)

            # Normalize one-way so the line ALWAYS points in the travel direction
            oneway = props.get("oneway") in ("yes", "true", "1") \
                or props.get("junction") == "roundabout"
            if props.get("oneway") == "-1":
                coords.reverse()
                oneway = True

            line = LineString(coords)
            area = line.buffer(width / 2, cap_style="flat", join_style="round")
            entry.update({
                "kind": kind,
                "width": width,
                "oneway": oneway,
                "layer": int(props.get("layer", 0) or 0),
                "bridge": "bridge" in props,
                "tunnel": "tunnel" in props,
                "line": [round_pt(c) for c in coords],
                "polys": [poly_to_rings(p) for p in polys_of(area.simplify(0.1))],
            })
            out["roads"].append(entry)

        elif "building" in props:
            polys = polys_of(geom)
            if not polys:
                continue
            levels = parse_width(props.get("building:levels"))
            entry.update({
                "kind": props["building"],
                "levels": levels if levels else 1,
                "polys": [poly_to_rings(p) for p in polys],
            })
            out["buildings"].append(entry)

        elif "waterway" in props:
            if not isinstance(geom, LineString):
                continue
            area = geom.buffer(1.5, cap_style="round")
            entry.update({
                "kind": props["waterway"],
                "line": [round_pt(c) for c in geom.coords],
                "polys": [poly_to_rings(p) for p in polys_of(area)],
            })
            out["waterways"].append(entry)

        else:
            kind = props.get("landuse") or props.get("natural") or props.get("leisure")
            polys = polys_of(geom)
            if kind and polys:
                entry.update({
                    "kind": kind,
                    "polys": [poly_to_rings(p) for p in polys],
                })
                out["landuse"].append(entry)

    out["meta"] = {
        "crs": TARGET_CRS,
        "origin_utm": [origin_x, origin_y],
        "size_m": [round(maxx - minx, 1), round(maxy - miny, 1)],
        "bounds_m": output_bounds(out),
        "attribution": "© OpenStreetMap contributors (ODbL)",
        "counts": {k: len(v) for k, v in out.items() if isinstance(v, list)},
    }

    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    print("Wrote", dst)
    print(out["meta"])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="OSM GeoJSON export")
    parser.add_argument("output", help="output map.json")
    parser.add_argument(
        "--origin-utm",
        nargs=2,
        type=float,
        metavar=("X", "Y"),
        default=DEFAULT_ORIGIN_UTM,
        help="pinned origin in EPSG:31982 meters",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    origin = args.origin_utm
    main(str(args.input), str(args.output), (float(origin[0]), float(origin[1])))
