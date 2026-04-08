# CLAUDE.md — steieRmark

This file gives you the full context needed to modify this project.

## What this is

A single-file Shiny app (`app.R`) that renders a full-screen Leaflet map of:
- 8 protected-area polygon layers covering all of Steiermark
- Gemeinde (municipality) boundaries for the Bruck-Mürzzuschlag district (GID_2 = `AUT.6.1_2`)
- One Hauptort (main settlement) point per Gemeinde

Stack: R, `shiny`, `leaflet`, `sf`, `geodata`. No tidyverse anywhere — base R only.

---

## Files

### `app.R`
The entire application. Structured in four sections:

1. **Data loading** (top-level, runs once at startup)
2. **Popup builders** (vectorised `paste0` — one string per feature)
3. **Layer registry** (`layers` list + swatch label generation)
4. **Shiny UI/server** (single `renderLeaflet` call)

### `bruck_murzzuschlag.ipynb`
Exploratory R notebook (IRkernel). Used to prototype the administrative boundary + Hauptorte pipeline before it was moved into `app.R`. Useful reference if the data loading logic needs debugging.

### `nature/`
Eight zipped shapefiles from the Land Steiermark GIS portal. All are EPSG:4258 (ETRS89), all polygon. The app reads them directly from the zips via `/vsizip/` — do not unzip. A `nature_extracted/` directory may exist locally from earlier exploration; it is gitignored and not used by the app.

### `STATISTIK_AUSTRIA_ORT_MP_20250101.zip`
Statistics Austria settlement midpoints (Ortschaft Mittelpunkte), ~17k points for all of Austria. CRS is EPSG:31287 (MGI / Austria Lambert). The app reprojects to WGS84 and spatially filters to the Bruck-Mürzzuschlag district.

---

## How `app.R` works

### Protected-area layers
Each zip is read with `st_read("/vsizip/...")` and transformed to EPSG:4326. `wasserschutzgebiete_stmk` (6031 features) is also run through `st_make_valid()`, `st_simplify(dTolerance = 0.001)`, and a geometry-type filter to drop the one GEOMETRYCOLLECTION that `st_simplify` can produce.

### Administrative boundaries (`bruck`)
Downloaded from GADM v4.1 via `geodata::gadm("AUT", level=3, path=...)`. Filtered to `GID_2 == "AUT.6.1_2"` (Bruck-Mürzzuschlag district). Gives 19 Gemeinden.

The `path` argument uses `Sys.getenv("GADM_PATH", tempdir())` so that:
- **locally**: data downloads to `tempdir()` on first run
- **in Docker**: uses the pre-baked `/srv/geodata` (no network needed)

### Hauptorte selection
For each of the 19 Gemeinden, one representative Ortschaft is selected from the Statistics Austria point dataset using a priority chain:

1. Exact UTF-8 name match with the Gemeinde name
2. Ortschaft name starts with the Gemeinde name (catches "Aflenz" → "Aflenz Kurort")
3. Gemeinde name starts with the Ortschaft name (catches "Pernegg an der Mur" → "Pernegg")
4. Fallback: Ortschaft closest to the Gemeinde centroid

The Statistics Austria zip uses **ISO-8859-1 / Latin-1** encoding for the `g_name` field. GADM uses UTF-8. `iconv(g_name, from="latin1", to="UTF-8")` is applied before any name comparison.

### Layer control with colored swatches
Leaflet in R renders group names as raw HTML in the layers control panel. Each layer's group name is an HTML string containing an inline `<span>` with the layer colour as `background`. The same HTML string is used for both `group=` in `addPolygons`/`addCircleMarkers` and in `overlayGroups` — they must match exactly.

The `swatch(color, name, shape)` helper (in `app.R`) builds these strings. Use `shape="circle"` for point layers.

---

## Known quirks

| Issue | Where | Fix applied |
|---|---|---|
| `st_simplify` produces GEOMETRYCOLLECTION | `wasserschutzgebiete_stmk` | Filter rows: `st_geometry_type(x) %in% c("POLYGON","MULTIPOLYGON")` |
| Invalid geometries | `wasserschutzgebiete_stmk` (12 features) | `st_make_valid()` before simplify |
| Latin-1 encoding in Ortschaft names | `STATISTIK_AUSTRIA_ORT_MP` | `iconv(from="latin1", to="UTF-8")` |
| GADM name garbling | "Sanktnz im Mürztal" (should be "Stanz im Mürztal") | Centroid-nearest fallback handles it |

---

## Docker

```dockerfile
FROM rocker/geospatial:4.4   # ships sf, terra, GDAL, GEOS, PROJ
```

`rocker/geospatial` already contains `sf` and `terra`. Only `shiny`, `leaflet`, and `geodata` need to be added. GADM data is downloaded during `docker build` (one RUN layer) and baked into the image under `/srv/geodata`. The `GADM_PATH` env var points `app.R` at this directory.

To rebuild after changing `app.R` or the data files:
```bash
docker compose build
docker compose up -d
```

To upgrade the GADM data version, change the `gadm()` call in the `RUN` layer of the Dockerfile and rebuild.
