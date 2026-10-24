SHELL := /bin/bash
.DEFAULT_GOAL := help

MAP_SOURCE ?= data/export_0002.geojson

.PHONY: help check smoke minimap-smoke vehicle-smoke animation-smoke bench lint format map

help:
	@echo "make check      Syntax, import scan, and autoload-aware compile check"
	@echo "make smoke      Headless map + vegetation smoke test (runs check first)"
	@echo "make minimap-smoke  Headless mini-map rendering and interaction test (runs check first)"
	@echo "make vehicle-smoke  Headless vehicle handling and enter/exit test (runs check first)"
	@echo "make animation-smoke  Headless entity animation state test (runs check first)"
	@echo "make bench      Measure runtime map load time, counts, and memory"
	@echo "make lint       Run gdlint via uv (does not modify files)"
	@echo "make format     Rewrite GDScript with gdformat via uv"
	@echo "make map        Regenerate data/map.json from $(MAP_SOURCE)"

check:
	@tools/check.sh

smoke: check
	@tools/smoke.sh

minimap-smoke: check
	@tools/minimap_smoke.sh

vehicle-smoke: check
	@tools/vehicle_smoke.sh

animation-smoke: check
	@tools/animation_smoke.sh

bench: check
	@tools/bench.sh

lint:
	uv run --python 3.13 --with gdtoolkit gdlint autoloaders resources scripts tests

format:
	uv run --python 3.13 --with gdtoolkit gdformat autoloaders resources scripts tests

map:
	uv run --python 3.13 --with shapely --with pyproj --with numpy python tools/osm_to_godot.py $(MAP_SOURCE) data/map.json
