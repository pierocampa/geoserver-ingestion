# Utilities for geo-spatial data ingestion

* [Content](#content)
* [Technologies](#technologies)
* [Installation](#installation)
* [Usage](#usage)
  * [ingest_shp](#ingest_shp)
  * [unpublish_shp](#unpublish_shp)
  * [manage_datasets](#manage_datasets)
  * [fetch_type](#fetch_type)
* [Examples](#examples)

## Content

This project contains command-line utilities for managing the publication of geo-spatial
datasets onto a **PostGIS**/**GeoServer** stack.

The content is structured as follows:

| file | category | description |
|:------------:|:------------:|:------------|
| `install` | installation | *installs the utilities onto a given directory* |
| `ingest_shp` | slave script | *ingestion and publishing of a single shapefile* |
|`unpublish_shp` | slave script | *unpublishing and purging of a single shapefile* |
|`manage_datasets` | master script | *bulk processing of  datasets under a directory* |
|`fetch_ftype` | aux | *fetches the feature type of a GeoServer vector layer* |
|`pg_conn.default` | connection file | *template of a PostgreSQL connection file* |
|`gs_conn.default` | connection file | *template of a GeoServer connection file* |
|`docs/` | documentation | *docs and diagrams* |

### Connection files

All utilities refer to *connection files* in order to define the connection to both the PostgreSQL/PostGIS database and the GeoServer instance. These files are shell files declaring connection variables that link to a given resource, like:

```sh
# pg_conn.default
PGHOST=192.168.1.?
PGPORT=5432
PGUSER=my_pg_user
PGDATABASE=db_name
PGSCHEMA=db_schema
```

for the connection with the database, and:

```sh
# gs_conn.default
GSUSER=gs_admin
GSURL=https://acme.com/geoserver
GSWORKSPACE=gs_workspace
GSDATASTORE=gs_datastore
GSPWD_FILE=gs_pwd.des3
```

for the connection with GeoServer.

It is recommended that you allow the database user `$PSUSER` to commit to database without password prompt (see the PostgreSQL docs on how to achieve that).

Regarding the GeoServer password file: encode the GeoServer password onto the specified file with the DES3 encryption algorithm, using the `$GSWORKSPACE` as encryption key:

```sh
echo $GS_PASSWORD | openssl enc -e -des3 -base64 -pbkdf2 -pass pass:$GSWORKSPACE > gs_pwd.des3
```


## Technologies

All utilities use [bash](https://www.gnu.org/software/bash/) as shell interpreter.

HTTP requests are made with [curl](https://curl.se/), while geospatial data are loaded into the database via [PostGIS](https://postgis.net/docs/manual-3.0/) CLI tools.

[openssl](https://www.openssl.org/) is used for password decryption.

## Installation

```sh
./install $TARGET_DIR
```

This will copy the utilities in the `$TARGET_DIR` directory.

Now define properly your `pg_conn` and `gs_conn` connection files into the same `$TARGET_DIR`, then you can start managing your datasets.

## Usage

### `ingest_shp`

Ingestion and publishing of a single shapefile.  
IMPORTANT: note that the name of the dataset (both as in PostGIS table name, and as in GeoServer layer) will automatically turn to all-lowercase letters.

**USAGE**

```sh
ingest_shp SHP_BASENAME --srid SRID [OPTION]
```

**SHP_BASENAME**  
The basename of the shapefile to be ingested in the geo-database.  
This can also be a path, but the extension of the file shall not be specified.

**[--srid, -s] SRID**  
The SRID code of the shapefile's projection.

**[--publish, -p]**  
Option to publish the ingested feature to GeoServer datastore.  
This requires that files `SHP_BASENAME.ftype.xml` and `SHP_BASENAME.sld` both exist.  
See GeoServer REST API to see examples of feature type descriptions and styles, eg.:  
<sub>*https://GEOSERVER/rest/workspaces/{workspace}/datastores/{datastore}/featuretypes/{featuretype}.xml*</sub>  
<sub>*https://GEOSERVER/rest/workspaces/{workspace}/styles/{style}.xml*</sub>

**[--dry-run|-n]**  
Switches to dry run test: prints out commands without hitting the database nor GeoServer.

**[--help|-h]**  
Prints this text.


### `unpublish_shp`

Unpublishing and purge of a single shapefile.

**USAGE**

```sh
unpublish_shp LAYER_NAME [OPTION]
```

**LAYER_NAME**  
The name of the GeoServer layer (and PostGIS table) that has to be unpublished.

**[--drop, -d]**  
Option to additionally drop the data from the PostGIS database.

**[--keep-style, -s]**  
Option to avoid deleting the layer style definition from the GeoServer collection.

**[--dry-run, -n]**  
Switches to dry run test: prints out commands without hitting the database nor GeoServer.

**[--help, -h]**  
Prints this text.


### `manage_datasets`

Bulk management of datasets under a given directory.

It relies on the `ingest_shp`, `unpubl_shp` and `fetch_type` slave scripts (all additional arguments to a manage_dataset call are passed on to those scripts, e.g. you can append `--dry-run` for bulk dry-run on a folder).

Additionally it requires that all datasets aer accompained by a `.srid` file containing the EPSG code of the geospatial projection of the datasets to be used as `--srid` argument on slave scripts.  

**USAGE**

```sh
manage_dataset ACTION FOLDER [OPTION]
```

**ACTION**
* **[load, l]**  
Just load the datasets into the database.

* **[publish, p]**  
Load the datasets into the PostGIS database (if not yet stored), then publish them as GeoServer layers.

* **[unpublish, u]**  
Unpublish the GeoServer layers, but keep the data in the database.

* **[drop, d]**  
Unpublish the GeoServer layers, then drop the data from the database.

* **[sync-ftype, sf]**  
Synchronizes the local feature type definition of a layer with that of the published layer.

**FOLDER**  
Root folder where to look for datasets to be managed.
The script will identify a dataset by looking for any .shp script under the directory, and will execute the action on the dataset based on the following conditions:

1. **`l`** and **`p`** actions will be executed if a file called *`update`* is found in the directory;
1. **`u`** and **`d`** actions will be executed if a file called *`delete`* is found in the directory;
1. **`sf`** action will be executed if a file called *`sync`* is found in the directory;

NOTE: use the **`--force`** argument to force the execution of the action on all datasets.

**OPTION**  
**[--force, -f]**  
Forces the action to be executed on all datasets found under the given `FOLDER`.

**[--dry-run, -n]**  
Dry run test: prints out commands without hitting the database nor GeoServer.

**[--help, -h]**  
Prints this text.


### `fetch_type`

Downloads the XML feature type description of a GeoServer layer.

**USAGE**

```sh
fetch_ftype LAYER_NAME
```

**LAYER_NAME**  
The name of the layer published in GeoServer instance.

**[--help, -h]**  
Prints this text.



## Examples

```sh
# Load and publish a single shapefile:
./ingest_shp Burundi_Pop --srid 32735 --publish

# Unpublish and purge a dataset, but keep style SLD definition in GeoServer catalog (note layer name is lower-case):
./unpublish_shp burundi_pop --drop --keep-style

# Bulk loading of all marked datasets in a folder (recursively):
./manage_datasets publish /data/root/folder/

# Dry-run bulk unpublishing all marked layers from GeoServer:
./manage_datasets unpublish /data/root/folder/ --dry-run

# Sync the local feature type definition of all marked datasets with the published version:
./manage_datasets sf /data/root/folder
```

### Credits

[![EURAC Research](https://www.eurac.edu/Style%20Library/logoEURAC.jpg)](https://www.eurac.edu/en/pages/default.aspx)

