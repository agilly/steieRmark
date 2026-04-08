FROM rocker/geospatial:4.4

# Install R packages not already in rocker/geospatial
RUN install2.r --error --skipinstalled \
    shiny \
    leaflet \
    geodata

# Pre-download GADM Austria level 3 so the app never needs outbound network at runtime
ENV GADM_PATH=/srv/geodata
RUN mkdir -p /srv/geodata && \
    Rscript -e "library(geodata); gadm('AUT', level=3, path='/srv/geodata')"

WORKDIR /srv/shiny
COPY app.R .
COPY nature/ nature/
COPY STATISTIK_AUSTRIA_ORT_MP_20250101.zip .

EXPOSE 3838

CMD ["Rscript", "-e", "shiny::runApp('/srv/shiny', host='0.0.0.0', port=3838)"]
