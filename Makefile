SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help check smoke lint format map

help:
	@echo "make check      Syntax, import scan, and autoload-aware compile check"
	@echo "make smoke      Headless map + vegetation smoke test (runs check first)"
	@echo "make lint       Run gdlint via uv (does not modify files)"
	@echo "make format     Rewrite GDScript with gdformat via uv"
	@echo "make map        Regenerate data/map.json from data/export.geojson"

check:
	@tools/check.sh

smoke: check
	@tools/smoke.sh

lint:
	uv run --python 3.13 --with gdtoolkit gdlint autoloaders resources scripts tests

format:
	uv run --python 3.13 --with gdtoolkit gdformat autoloaders resources scripts tests

map:
	uv run --python 3.13 --with shapely --with pyproj --with numpy python tools/osm_to_godot.py data/export.geojson data/map.json
