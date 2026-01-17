# Custom OpenEO Executor Image with libexpat fix and load_stac patch
# Base image: official openeo-argoworkflows executor
FROM ghcr.io/eodcgmbh/openeo-argoworkflows:executor-2025.5.1

# Switch to root to install system packages
USER root

# Install libexpat (required by rasterio)
RUN apt-get update && \
    apt-get install -y --no-install-recommends libexpat1 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy patched load.py to fix CRS extraction from STAC items
COPY load_patched.py /opt/openeo_argoworkflows_executor/.venv/lib/python3.11/site-packages/openeo_processes_dask/process_implementations/cubes/load.py

# Copy fixed io.py to fix load_collection variable initialization bug
COPY io_fixed.py /opt/openeo_argoworkflows_executor/extra_processes/process_implementations/io.py

# Copy fixed stac.py to handle CRS reading from netCDF files
COPY stac_fixed.py /opt/openeo_argoworkflows_executor/stac.py

# Switch back to non-root user
USER 1000
