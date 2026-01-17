import logging
import numpy as np
import os
import pyproj
import pystac_client
import xarray as xr

from odc.stac import stac_load
from pathlib import Path
from pystac.extensions import raster
from typing import Optional, Union
from openeo_processes_dask.process_implementations.data_model import (
    RasterCube
)
from openeo_processes_dask.process_implementations.cubes._filter import filter_bbox
from openeo_pg_parser_networkx.pg_schema import BoundingBox, GeoJson, TemporalInterval

__all__ = ["load_collection", "save_result"]

logger = logging.getLogger(__name__)


def load_collection(
    id: str,
    spatial_extent: Optional[Union[BoundingBox, dict, str, GeoJson]] = None,
    temporal_extent: Optional[TemporalInterval] = None,
    bands: Optional[list[str]] = None,
    properties: Optional[dict] = None,
    **kwargs,
):
    """Load a collection from the STAC API.

    This implementation fixes the variable initialization bug and adds
    better error handling and logging.
    """
    query_dict = {}

    query_dict["collections"] = [id]

    if spatial_extent is None:
        raise Exception(
            "No spatial extent was provided, will not load the entire x and y axis of the datacube."
        )
    elif temporal_extent is None:
        raise Exception(
            "No temporal extent was provided, will not load the entire temporal axis of the datacube."
        )

    if isinstance(spatial_extent, BoundingBox):
        query_dict["bbox"] = (
            spatial_extent.west,
            spatial_extent.south,
            spatial_extent.east,
            spatial_extent.north,
        )
    else:
        raise ValueError("Provided spatial extent could not be interpreted.")

    # Format datetime properly for STAC API (needs ISO format with time)
    datetime_parts = []
    for time in temporal_extent:
        if time != 'None' and time is not None:
            time_str = str(time.root) if hasattr(time, 'root') else str(time)
            # Add time component if not present
            if 'T' not in time_str:
                time_str = f"{time_str}T00:00:00Z"
            datetime_parts.append(time_str)

    query_dict["datetime"] = "/".join(datetime_parts) if datetime_parts else None
    logger.info(f"Formatted datetime: {query_dict['datetime']}")

    if "STAC_API_URL" not in os.environ:
        raise Exception("STAC URL Not available in executor config.")

    logger.info(f"Connecting to STAC API: {os.environ['STAC_API_URL']}")
    logger.info(f"Query parameters: {query_dict}")

    catalog = pystac_client.Client.open(os.environ["STAC_API_URL"])
    results = catalog.search(**query_dict, limit=100)

    result_items = list(results.items())

    if not result_items:
        bbox = query_dict.get('bbox', 'N/A')
        datetime_range = query_dict.get('datetime', 'N/A')
        error_msg = (
            f"No data found for collection '{id}' with the given parameters:\n"
            f"  - Bounding box: {bbox}\n"
            f"  - Time range: {datetime_range}\n"
            f"Please verify that data exists for this location and time period."
        )
        logger.error(error_msg)
        raise Exception(error_msg)

    logger.info(f"Found {len(result_items)} items")

    example_item = result_items[0]

    # Extract CRS from item properties
    crs = None
    if "proj:wkt2" in example_item.properties.keys():
        crs = pyproj.CRS.from_wkt(example_item.properties["proj:wkt2"])
        logger.info(f"Using CRS from proj:wkt2: {crs.name}")
    elif "proj:epsg" in example_item.properties.keys():
        crs = pyproj.CRS.from_epsg(example_item.properties["proj:epsg"])
        logger.info(f"Using CRS from proj:epsg: {example_item.properties['proj:epsg']}")
    else:
        # Default to EPSG:4326 if no CRS found
        crs = pyproj.CRS.from_epsg(4326)
        logger.warning("No CRS found in item properties, defaulting to EPSG:4326")

    # Initialize variables with defaults
    resolution = None
    nodata = None
    dtype = None

    # Try to extract raster metadata from item
    if raster.RasterExtension.has_extension(example_item):
        for asset in example_item.get_assets().values():
            if 'raster:bands' in asset.extra_fields.keys():
                for band in asset.extra_fields['raster:bands']:
                    if 'spatial_resolution' in band and resolution is None:
                        resolution = band['spatial_resolution']
                    if 'nodata' in band and nodata is None:
                        nodata = band['nodata']
                    if 'data_type' in band and dtype is None:
                        dtype = band['data_type']
            if resolution and nodata and dtype:
                break

    # If resolution not found, determine from CRS
    if resolution is None:
        crs_measurement = crs.axis_info[0].unit_name if crs.axis_info else 'metre'

        if crs_measurement == 'metre':
            resolution = 10  # Default 10m for metric CRS
        elif crs_measurement == 'degree':
            resolution = 0.0001  # ~10m at equator
        else:
            resolution = 10  # Default fallback

        logger.info(f"Resolution not found in metadata, using default: {resolution} ({crs_measurement})")
    else:
        logger.info(f"Using resolution from metadata: {resolution}")

    # Build kwargs for stac_load
    load_kwargs = {}

    if dtype:
        load_kwargs["dtype"] = dtype
        # Ensure nodata matches dtype
        if "int" in dtype and isinstance(nodata, float):
            nodata = int(nodata)

    if nodata is not None:
        load_kwargs["nodata"] = nodata

    # Filter to only load "data" asset (exclude thumbnails, tilejson, etc.)
    # Check what assets are available
    if result_items:
        available_assets = list(result_items[0].assets.keys())
        logger.info(f"Available assets: {available_assets}")

        # Select only data-related assets
        data_assets = [a for a in available_assets if a in ['data', 'visual', 'B01', 'B02', 'B03', 'B04', 'B05', 'B06', 'B07', 'B08', 'B8A', 'B09', 'B10', 'B11', 'B12']]
        if not data_assets and 'data' not in available_assets:
            # Fallback: exclude known non-data assets
            data_assets = [a for a in available_assets if a not in ['thumbnail', 'tilejson', 'preview', 'metadata']]

        if data_assets:
            load_kwargs["bands"] = data_assets
            logger.info(f"Loading only these bands/assets: {data_assets}")

    logger.info(f"Loading data with CRS={crs}, resolution={resolution}, kwargs={load_kwargs}")

    lazy_xarray = stac_load(
        result_items,
        crs=crs,
        resolution=resolution,
        chunks={"x": 2048, "y": 2048},
        **load_kwargs
    ).to_array(dim='bands')

    logger.info(f"Loaded xarray with shape: {lazy_xarray.shape}, dims: {lazy_xarray.dims}")

    # Clip to the original bounding box
    return filter_bbox(lazy_xarray, extent=spatial_extent)


def save_result(
    data: RasterCube,
    format: str = 'netcdf',
    options: Optional[dict] = None,
):
    """Save the result data cube to a file."""

    def clean_unused_coordinates(ds):
        """
        Remove all coordinates that are not used in the DataArray dimensions.
        """
        used_dims = set()
        for var in ds.dims:
            used_dims.update(ds[var].dims)

        for coord in list(ds.coords):
            if coord not in used_dims:
                ds = ds.drop_vars(coord)
        return ds

    import uuid

    logger.info(f"Saving result data with shape: {data.shape if hasattr(data, 'shape') else 'unknown'}")
    logger.info(f"Data attrs: {data.attrs}")

    _id = str(uuid.uuid4())

    # Get the results path from environment
    results_path = os.environ.get("OPENEO_RESULTS_PATH", "/tmp/results")
    os.makedirs(results_path, exist_ok=True)

    destination = Path(results_path) / f"{_id}.nc"

    dim = data.openeo.band_dims[0] if data.openeo.band_dims else None

    # Get CRS from rio accessor (rioxarray)
    crs = None
    if hasattr(data, 'rio') and data.rio.crs is not None:
        crs = data.rio.crs
        logger.info(f"Got CRS from rio accessor: {crs}")
    elif 'crs' in data.attrs:
        crs = data.attrs['crs']
        logger.info(f"Got CRS from attrs: {crs}")

    # Write CRS to the data using rioxarray before converting to dataset
    if crs is not None:
        import rioxarray  # noqa - needed for .rio accessor
        from pyproj import CRS as PyprojCRS

        # Ensure CRS is a proper pyproj CRS object
        if isinstance(crs, str):
            try:
                crs = PyprojCRS.from_user_input(crs)
            except Exception as e:
                logger.warning(f"Could not parse CRS string: {e}")
                crs = None

        if crs is not None:
            # Write CRS to the data - this embeds it properly for rio to read later
            data = data.rio.write_crs(crs)
            logger.info(f"Wrote CRS to data: {data.rio.crs}")

    out_data: xr.Dataset = data.to_dataset(
        dim=dim, name="name" if not dim else None, promote_attrs=True
    )

    # Write CRS to dataset as well
    if crs is not None:
        out_data = out_data.rio.write_crs(crs)

    dtype = "float32"
    comp = dict(zlib=True, complevel=5, dtype=dtype)

    encoding = {var: comp for var in out_data.data_vars}
    out_data = clean_unused_coordinates(out_data)

    logger.info(f"Writing netCDF to: {destination}")
    logger.info(f"Dataset CRS before save: {out_data.rio.crs if hasattr(out_data, 'rio') else 'N/A'}")
    out_data.to_netcdf(path=destination, encoding=encoding)
    logger.info(f"Successfully saved result to: {destination}")
