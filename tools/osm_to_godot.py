#!/usr/bin/env python3
"""
Converts an OSM GeoJSON export (Overpass Turbo / osmium export) into a single
JSON file that Godot 4 can load easily.

Usage:
    python osm_to_godot.py export.geojson map.json

Output coordinates are in METERS, relative to the center of the data, with Y
flipped (Godot: +Y is down, so north is -Y). Scaling to pixels is done in Godot.

Dependencies:  shapely, pyproj
    sudo pacman -S python-shapely python-pyproj
"""
import json
import sys

from pyproj import Transformer
from shapely.affinity import affine_transform
from shapely.geometry import LineString, MultiPolygon, Polygon, shape
import numpy as np
import shapely

# SIRGAS 2000 / UTM zone 22S (good for Santa Maria)
TARGET_CRS = "EPSG:31982"

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
    "name", "alt_name", "highway", "building", "building:levels", "height",
    "oneway", "lanes", "maxspeed", "surface", "bridge", "tunnel", "layer",
    "junction", "landuse", "natural", "leisure", "waterway", "amenity",
    "shop", "railway", "addr:street", "addr:housenumber", "addr:postcode",
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


def main(src, dst):
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

    # 2) Origin = center of the bounding box of everything
    minx = min(g.bounds[0] for _, _, g in items)
    miny = min(g.bounds[1] for _, _, g in items)
    maxx = max(g.bounds[2] for _, _, g in items)
    maxy = max(g.bounds[3] for _, _, g in items)
    cx, cy = (minx + maxx) / 2, (miny + maxy) / 2

    # x' = x - cx ; y' = -(y - cy)   (flip Y)
    matrix = [1, 0, 0, -1, -cx, cy]

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
        "origin_utm": [round(cx, 2), round(cy, 2)],
        "size_m": [round(maxx - minx, 1), round(maxy - miny, 1)],
        "attribution": "© OpenStreetMap contributors (ODbL)",
        "counts": {k: len(v) for k, v in out.items() if isinstance(v, list)},
    }

    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    print("Wrote", dst)
    print(out["meta"])


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: python osm_to_godot.py input.geojson output.json")
    main(sys.argv[1], sys.argv[2])
