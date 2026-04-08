# steieRmark

Interactive Leaflet map of protected nature zones across Steiermark, Austria, with administrative boundaries and main settlements (Hauptorte) for the Bruck-Mürzzuschlag district.

## Repository layout

```
steiermark/
├── app.R                                    # Shiny/Leaflet application
├── bruck_murzzuschlag.ipynb                 # Exploratory notebook (R kernel)
├── nature/                                  # Protected-area shapefiles (zipped)
│   ├── Europaschutzgebiete.zip              # Natura 2000 / EU protection zones
│   ├── Landschaftsschutzgebiete.zip         # Landscape protection areas
│   ├── Naturparke.zip                       # Nature parks
│   ├── Naturschutzgebiete_a.zip             # Nature reserves – category A
│   ├── Naturschutzgebiete_b.zip             # Nature reserves – category B
│   ├── Naturschutzgebiete_c.zip             # Nature reserves – category C
│   ├── Wasserschongebiete.zip               # Water conservation areas
│   └── wasserschutzgebiete_stmk.zip         # Water protection zones (Styria)
├── STATISTIK_AUSTRIA_ORT_MP_20250101.zip    # Statistics Austria: settlement midpoints
├── Dockerfile
├── docker-compose.yml
└── .dockerignore
```

## Data sources

| Dataset | Source |
|---|---|
| Protected areas (`nature/`) | Land Steiermark GIS open-data portal |
| Settlement midpoints | Statistik Austria – Ortschaft Mittelpunkte (2025-01-01) |
| Administrative boundaries | GADM v4.1 (downloaded at build time via the `geodata` R package) |

## Running locally

Requires R ≥ 4.1 with packages: `shiny`, `leaflet`, `sf`, `geodata`.

```r
shiny::runApp(".")
```

GADM data is downloaded on first run and cached in `tempdir()`.

## Deployment

```bash
git clone git@github.com:agilly/steieRmark.git
cd steieRmark
docker compose up -d
```

The app is served at **http://localhost:3838**.

The Docker build pre-downloads GADM Austria level 3 into the image so the container requires no outbound internet access at runtime.

To expose it publicly, put a reverse proxy (nginx, Caddy) in front and forward to port 3838.
