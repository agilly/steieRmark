library(shiny)
library(leaflet)
library(sf)
library(geodata)

# ---------------------------------------------------------------------------
# Data loading — all at startup so the map renders immediately on first visit
# ---------------------------------------------------------------------------

base_dir <- "nature"

read_layer <- function(zip_name, shp_name = zip_name) {
  path <- paste0("/vsizip/", file.path(base_dir, paste0(zip_name, ".zip")),
                 "/", shp_name, ".shp")
  st_read(path, quiet = TRUE) |> st_transform(4326)
}

europaschutz <- read_layer("Europaschutzgebiete")
landschaft   <- read_layer("Landschaftsschutzgebiete")
naturparke   <- read_layer("Naturparke")
nsg_a        <- read_layer("Naturschutzgebiete_a")
nsg_b        <- read_layer("Naturschutzgebiete_b")
nsg_c        <- read_layer("Naturschutzgebiete_c")
wasserschon  <- read_layer("Wasserschongebiete")
wasserschutz <- read_layer("wasserschutzgebiete_stmk") |>
  st_make_valid() |>
  st_simplify(preserveTopology = TRUE, dTolerance = 0.001) |>
  (\(x) x[st_geometry_type(x) %in% c("POLYGON", "MULTIPOLYGON"), ])()

# ---------------------------------------------------------------------------
# Gemeindegrenzen + Hauptorte for Bruck-Mürzzuschlag
# ---------------------------------------------------------------------------

bruck <- st_as_sf(gadm("AUT", level = 3, path = Sys.getenv("GADM_PATH", tempdir()))) |>
  (\(x) x[x$GID_2 == "AUT.6.1_2", ])() |>
  st_transform(4326)

ho_all    <- st_read(
  paste0("/vsizip/STATISTIK_AUSTRIA_ORT_MP_20250101.zip",
         "/STATISTIK_AUSTRIA_ORT_MP_20250101.shp"),
  quiet = TRUE
) |> st_transform(4326)

ho_joined <- st_join(st_filter(ho_all, bruck), bruck[, c("GID_3", "NAME_3")])
ho_joined$g_name_utf8 <- iconv(ho_joined$g_name, from = "latin1", to = "UTF-8")

bruck_cents    <- st_centroid(st_geometry(bruck))
hauptorte_main <- do.call(rbind, lapply(seq_len(nrow(bruck)), function(i) {
  pts <- ho_joined[!is.na(ho_joined$GID_3) & ho_joined$GID_3 == bruck$GID_3[i], ]
  if (nrow(pts) == 0L) return(NULL)
  nm <- bruck$NAME_3[i]
  m  <- pts[pts$g_name_utf8 == nm, ]
  if (nrow(m) > 0) return(m[1, ])
  m  <- pts[startsWith(pts$g_name_utf8, nm), ]
  if (nrow(m) > 0) return(m[1, ])
  m  <- pts[startsWith(nm, pts$g_name_utf8), ]
  if (nrow(m) > 0) return(m[which.min(nchar(m$g_name_utf8)), ])
  pts[which.min(st_distance(pts, bruck_cents[i])), ]
}))

# ---------------------------------------------------------------------------
# Popup HTML builders
# ---------------------------------------------------------------------------

# Build one popup string per feature (vectorised paste0)
fmt_ha <- function(x) paste0(round(x, 1), " ha")

popup_eu <- paste0(
  "<b>", europaschutz$NAME, "</b><br>",
  "<span style='color:#888'>EU-Code:</span> ", europaschutz$EU_CODE, "<br>",
  "<span style='color:#888'>Kategorie:</span> ", europaschutz$KATEGORIE
)

popup_land <- paste0(
  "<b>", landschaft$NAME, "</b><br>",
  "<span style='color:#888'>Fläche:</span> ", fmt_ha(landschaft$FLAECHE_HA)
)

popup_park <- paste0(
  "<b>", naturparke$NAME, "</b><br>",
  "<span style='color:#888'>Fläche:</span> ", fmt_ha(naturparke$HECTARES)
)

popup_nsga <- paste0(
  "<b>", nsg_a$NAME, "</b><br>",
  "<span style='color:#888'>Fläche:</span> ", fmt_ha(nsg_a$HECTARES)
)

popup_nsgb <- paste0(
  "<b>", nsg_b$NAME, "</b><br>",
  "<span style='color:#888'>Kategorie:</span> ", nsg_b$KATEGORIE, "<br>",
  "<span style='color:#888'>Fläche:</span> ", fmt_ha(nsg_b$HECTARES)
)

popup_nsgc <- paste0(
  "<b>", nsg_c$NAME, "</b><br>",
  "<span style='color:#888'>Kategorie:</span> ", nsg_c$KATEGORIE, "<br>",
  "<span style='color:#888'>Fläche:</span> ", fmt_ha(nsg_c$HECTARES)
)

popup_wson <- paste0(
  "<b>", wasserschon$WSO_NAME, "</b><br>",
  "<span style='color:#888'>Typ:</span> ", wasserschon$WSO_TYP, "<br>",
  "<span style='color:#888'>Fläche:</span> ", fmt_ha(wasserschon$FLAECHE_HA)
)

popup_wstz <- paste0(
  "<b>", wasserschutz$ANL_SUBTYP, "</b><br>",
  "<span style='color:#888'>Typ:</span> ", wasserschutz$ANL_TYPE
)

# ---------------------------------------------------------------------------
# Layer registry  (name, data, popup, fill colour, HTML label with swatch)
# ---------------------------------------------------------------------------

swatch <- function(color, name, shape = "square") {
  radius <- if (shape == "circle") "50%" else "2px"
  paste0(
    "<span style='display:inline-block;width:12px;height:12px;",
    "border-radius:", radius, ";background:", color,
    ";margin-right:6px;vertical-align:middle'></span>", name
  )
}

layers <- list(
  list(name = "Europaschutzgebiete",      data = europaschutz, popup = popup_eu,   color = "#1a936f"),
  list(name = "Landschaftsschutzgebiete", data = landschaft,   popup = popup_land, color = "#52b788"),
  list(name = "Naturparke",               data = naturparke,   popup = popup_park, color = "#114b5f"),
  list(name = "Naturschutzgebiete A",     data = nsg_a,        popup = popup_nsga, color = "#0077b6"),
  list(name = "Naturschutzgebiete B",     data = nsg_b,        popup = popup_nsgb, color = "#7b2d8b"),
  list(name = "Naturschutzgebiete C",     data = nsg_c,        popup = popup_nsgc, color = "#e07a5f"),
  list(name = "Wasserschongebiete",       data = wasserschon,  popup = popup_wson, color = "#0096c7"),
  list(name = "Wasserschutzgebiete",      data = wasserschutz, popup = popup_wstz, color = "#023e8a")
)

# Add HTML label (swatch + name) to every layer entry
layers <- lapply(layers, function(l) {
  l$label <- swatch(l$color, l$name)
  l
})

layer_labels <- sapply(layers, `[[`, "label")

lbl_gemeinden <- swatch("#222222", "Gemeindegrenzen")
lbl_hauptorte <- swatch("#e63946", "Hauptorte", shape = "circle")

# ---------------------------------------------------------------------------
# UI — full-screen map, no chrome
# ---------------------------------------------------------------------------

ui <- fluidPage(
  tags$head(tags$style(HTML(
    "html, body { margin:0; padding:0; height:100%; overflow:hidden; }
     .leaflet-container { font-family: inherit; }"
  ))),
  leafletOutput("map", width = "100%", height = "100vh")
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server <- function(input, output, session) {

  output$map <- renderLeaflet({

    m <- leaflet() |>
      addProviderTiles(providers$CartoDB.Positron,  group = "CartoDB Light") |>
      addProviderTiles(providers$OpenStreetMap,      group = "OpenStreetMap") |>
      setView(lng = 14.85, lat = 47.20, zoom = 8)

    for (lyr in layers) {
      m <- addPolygons(
        m,
        data             = lyr$data,
        group            = lyr$label,
        color            = lyr$color,
        fillColor        = lyr$color,
        weight           = 1.2,
        opacity          = 0.85,
        fillOpacity      = 0.25,
        popup            = lyr$popup,
        highlightOptions = highlightOptions(
          weight      = 2.5,
          fillOpacity = 0.55,
          bringToFront = TRUE
        )
      )
    }

    m <- addPolygons(
      m,
      data             = bruck,
      group            = lbl_gemeinden,
      color            = "#222222",
      fillColor        = "#222222",
      weight           = 1.8,
      opacity          = 1,
      fillOpacity      = 0.04,
      popup            = paste0("<b>", bruck$NAME_3, "</b>"),
      highlightOptions = highlightOptions(
        weight = 3, fillOpacity = 0.15, bringToFront = TRUE
      )
    )

    m <- addCircleMarkers(
      m,
      data        = hauptorte_main,
      group       = lbl_hauptorte,
      radius      = 6,
      color       = "#ffffff",
      fillColor   = "#e63946",
      weight      = 1.5,
      opacity     = 1,
      fillOpacity = 0.9,
      label       = hauptorte_main$g_name_utf8,
      popup       = paste0(
        "<b>", hauptorte_main$g_name_utf8, "</b><br>",
        "<span style='color:#888'>Gemeinde:</span> ", hauptorte_main$NAME_3
      )
    )

    m |>
      addLayersControl(
        baseGroups    = c("CartoDB Light", "OpenStreetMap"),
        overlayGroups = c(layer_labels, lbl_gemeinden, lbl_hauptorte),
        options       = layersControlOptions(collapsed = FALSE)
      ) |>
      addScaleBar(position = "bottomleft") |>
      addMiniMap(position = "bottomright", toggleDisplay = TRUE, minimized = TRUE)
  })
}

shinyApp(ui, server)
