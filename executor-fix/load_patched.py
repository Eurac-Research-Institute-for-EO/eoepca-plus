import datetime
import json
import logging
from collections.abc import Iterator
from pathlib import PurePosixPath
from typing import Any, Callable, Dict, List, Optional, Tuple, Union
from urllib.parse import unquote, urljoin, urlparse

import planetary_computer as pc
import pyproj
import pystac_client
import stackstac
import xarray as xr
from openeo_pg_parser_networkx.pg_schema import BoundingBox, TemporalInterval
from stac_validator import stac_validator

from openeo_processes_dask.process_implementations.cubes._filter import (
    _reproject_bbox,
    filter_bands,
    filter_bbox,
    filter_temporal,
)
from openeo_processes_dask.process_implementations.data_model import RasterCube
from openeo_processes_dask.process_implementations.exceptions import (
    NoDataAvailable,
    TemporalExtentEmpty,
)

# "NoDataAvailable": {
#     "message": "There is no data available for the given extents."
# },
# "TemporalExtentEmpty": {
#     "message": "The temporal extent is empty. The second instant in time must always be greater/later than the first instant in time."
# }
__all__ = ["load_stac"]

logger = logging.getLogger(__name__)


def _validate_stac(url):
    logger.debug(f"Validating the provided STAC url: {url}")
    stac = stac_validator.StacValidate(url)
    is_valid_stac = stac.run()
    if not is_valid_stac:
        raise Exception(
            f"The provided link is not a valid STAC. stac-validator message: {stac.message}"
        )
    if len(stac.message) == 1:
        try:
            asset_type = stac.message[0]["asset_type"]
        except:
            raise Exception(f"stac-validator returned an error: {stac.message}")
    else:
        raise Exception(
            f"stac-validator returned multiple items, not supported yet. {stac.message}"
        )
    return asset_type


def _search_for_parent_catalog(url):
    parsed_url = urlparse(url)
    root_url = parsed_url.scheme + "://" + parsed_url.netloc
    catalog_url = root_url
    url_parts = PurePosixPath(unquote(parsed_url.path)).parts
    collection_id = url_parts[-1]
    for p in url_parts:
        if p != "/":
            catalog_url = catalog_url + "/" + p
        try:
            asset_type = _validate_stac(catalog_url)
        except Exception as e:
            logger.debug(e)
            continue
        if asset_type == "CATALOG":
            break
    if asset_type != "CATALOG":
        raise Exception(
            "It was not possible to find the root STAC Catalog starting from the provided Collection."
        )
    return catalog_url, collection_id


def _extract_crs_from_items(items):
    """Extract CRS (EPSG code) from STAC items.

    Tries to get CRS from:
    1. proj:epsg in item properties
    2. proj:wkt2 in item properties (convert to EPSG)
    3. proj:epsg in assets

    Returns tuple of (epsg_code, resolution) or (None, None) if not found.
    """
    epsg = None
    resolution = None

    for item in items:
        props = item.properties if hasattr(item, 'properties') else {}

        # Try proj:epsg first
        if 'proj:epsg' in props:
            epsg = props['proj:epsg']
            logger.info(f"Found proj:epsg in item properties: {epsg}")
            break

        # Try proj:wkt2
        if 'proj:wkt2' in props:
            try:
                crs = pyproj.CRS.from_wkt(props['proj:wkt2'])
                epsg = crs.to_epsg()
                if epsg:
                    logger.info(f"Extracted EPSG {epsg} from proj:wkt2")
                    break
            except Exception as e:
                logger.warning(f"Could not extract EPSG from proj:wkt2: {e}")

        # Try assets
        assets = item.assets if hasattr(item, 'assets') else {}
        for asset_name, asset in assets.items():
            asset_dict = asset.to_dict() if hasattr(asset, 'to_dict') else asset
            if 'proj:epsg' in asset_dict:
                epsg = asset_dict['proj:epsg']
                logger.info(f"Found proj:epsg in asset {asset_name}: {epsg}")
                break
        if epsg:
            break

    # Try to determine resolution from item metadata
    for item in items:
        props = item.properties if hasattr(item, 'properties') else {}

        # Check for gsd (ground sample distance)
        if 'gsd' in props:
            resolution = props['gsd']
            logger.info(f"Found gsd in properties: {resolution}")
            break

        # Check proj:transform
        if 'proj:transform' in props:
            transform = props['proj:transform']
            if isinstance(transform, (list, tuple)) and len(transform) >= 2:
                # GeoTransform format: [x_scale, x_skew, x_origin, y_skew, y_scale, y_origin]
                resolution = abs(transform[0])
                logger.info(f"Extracted resolution from proj:transform: {resolution}")
                break

    # Default resolution based on common satellite data
    if resolution is None:
        resolution = 10  # Default to 10m (common for Sentinel-2)
        logger.info(f"Using default resolution: {resolution}")

    return epsg, resolution


def load_stac(
    url: str,
    spatial_extent: Optional[BoundingBox] = None,
    temporal_extent: Optional[TemporalInterval] = None,
    bands: Optional[list[str]] = None,
    properties: Optional[dict] = None,
) -> RasterCube:
    asset_type = _validate_stac(url)

    if asset_type == "COLLECTION":
        # If query parameters are passed, try to get the parent Catalog if possible/exists, to use the /search endpoint
        if spatial_extent or temporal_extent or bands or properties:
            # If query parameters are passed, try to get the parent Catalog if possible/exists, to use the /search endpoint
            catalog_url, collection_id = _search_for_parent_catalog(url)

            # Check if we are connecting to Microsoft Planetary Computer, where we need to sign the connection
            modifier = pc.sign_inplace if "planetarycomputer" in catalog_url else None

            catalog = pystac_client.Client.open(catalog_url, modifier=modifier)

            query_params = {"collections": [collection_id]}

            if spatial_extent is not None:
                try:
                    spatial_extent_4326 = spatial_extent
                    if spatial_extent.crs is not None:
                        if not pyproj.crs.CRS(spatial_extent.crs).equals("EPSG:4326"):
                            spatial_extent_4326 = _reproject_bbox(
                                spatial_extent, "EPSG:4326"
                            )
                    bbox = [
                        spatial_extent_4326.west,
                        spatial_extent_4326.south,
                        spatial_extent_4326.east,
                        spatial_extent_4326.north,
                    ]
                    query_params["bbox"] = bbox
                except Exception as e:
                    raise Exception(f"Unable to parse the provided spatial extent: {e}")

            if temporal_extent is not None:
                start_date = None
                end_date = None
                if temporal_extent[0] is not None:
                    start_date = str(temporal_extent[0].to_numpy())
                if temporal_extent[1] is not None:
                    end_date = str(temporal_extent[1].to_numpy())
                query_params["datetime"] = [start_date, end_date]

            if properties is not None:
                query_params["query"] = properties

            items = catalog.search(**query_params).item_collection()

        else:
            # Load the whole collection wihout filters
            raise Exception(
                f"No parameters for filtering provided. Loading the whole STAC Collection is not supported yet."
            )

    elif asset_type == "ITEM":
        stac_api = pystac_client.stac_api_io.StacApiIO()
        stac_dict = json.loads(stac_api.read_text(url))
        items = stac_api.stac_object_from_dict(stac_dict)

    else:
        raise Exception(
            f"The provided URL is a STAC {asset_type}, which is not yet supported. Please provide a valid URL to a STAC Collection or Item."
        )

    # Extract CRS and resolution from items if not available in assets
    epsg, resolution = _extract_crs_from_items(items)

    # Build stackstac parameters
    stack_kwargs = {}
    if epsg is not None:
        stack_kwargs['epsg'] = epsg
        logger.info(f"Using EPSG {epsg} for stackstac")
    if resolution is not None:
        stack_kwargs['resolution'] = resolution
        logger.info(f"Using resolution {resolution} for stackstac")

    if bands is not None:
        stack = stackstac.stack(items, assets=bands, **stack_kwargs)
    else:
        stack = stackstac.stack(items, **stack_kwargs)

    if spatial_extent is not None:
        stack = filter_bbox(stack, spatial_extent)

    if temporal_extent is not None and asset_type == "ITEM":
        stack = filter_temporal(stack, temporal_extent)

    return stack


def load_url(url: str, format: str, options={}):
    import geopandas as gpd
    import requests

    if format not in ["GeoJSON", "JSON", "Parquet"]:
        raise Exception(
            f"FormatUnsuitable: Data can't be loaded with the requested input format {format}."
        )

    response = requests.get(url)
    if not response.status_code < 400:
        raise Exception(f"Provided url {url} unavailable. ")

    if "JSON" in format:
        url_json = response.json()

    if format == "GeoJSON":
        for feature in url_json.get("features", {}):
            if "properties" not in feature:
                feature["properties"] = {}
            elif feature["properties"] is None:
                feature["properties"] = {}
        if isinstance(url_json.get("crs", {}), dict):
            crs = url_json.get("crs", {}).get("properties", {}).get("name", 4326)
        else:
            crs = int(url_json.get("crs", {}))
        logger.info(f"CRS in geometries: {crs}.")

        gdf = gpd.GeoDataFrame.from_features(url_json, crs=crs)

    elif "Parquet" in format:
        import os

        import geoparquet as gpq

        file_name = url.split("/")[-1]

        with open(file_name, "wb") as file:
            file.write(response.content)

        file_size = os.path.getsize(file_name)
        if file_size > 0:
            logger.info(f"File downloaded successfully. File size: {file_size} bytes")

        gdf = gpq.read_geoparquet(file_name)
        os.system(f"rm -rf {file_name}")

    elif format == "JSON":
        return url_json

    import xvec

    if not hasattr(gdf, "crs"):
        gdf = gdf.set_crs("epsg:4326")

    columns = gdf.columns.values
    variables = []
    for geom in columns:
        if geom in [
            "geometry",
            "geometries",
        ]:
            geo_column = geom
        else:
            variables.append(geom)
    cube = xr.Dataset(
        data_vars={
            variable: ([geo_column], gdf[variable].values) for variable in variables
        },
        coords={geo_column: gdf[geo_column].values},
    ).xvec.set_geom_indexes(geo_column, crs=gdf.crs)

    return cube
