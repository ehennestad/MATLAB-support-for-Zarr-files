"""
Python wrapper module to delegate function calls to the Python tensorstore library.
The module has functions for creating Zarr files, writing to Zarr files and reading Zarr files

Copyright 2025 The MathWorks, Inc.
"""
import json
import numpy as np
import tensorstore as ts

def createKVStore(isRemote, objPath, bucketName="") -> dict:
    """
    Creates a KV store (a python dictionary) for reading or writing
    a Zarr file
    
    Parameters:
    - isRemote (bool): whether the resource to be accessed with this 
KV store is remote (S3) or local
    - objPath (str): path to local Zarr file or to S3 object    
    - bucketName (str): If file is remote, this should be the S3 bucket 
name 
    
    Returns:
    - KVStore (dict): Key-Value store as required by tensorstore to work 
with Zarr
    """
    KVStore = dict(path=objPath);
    
    if isRemote:
        KVStore['driver'] = 's3'
        KVStore['bucket'] = bucketName
    else:
        KVStore['driver'] = 'file'

    return KVStore

def createZarr(kvstore_schema, data_shape, chunk_shape, tstoreDataType, zarrDataType, compressor, fillvalue):
    """
    Creates a new Zarr array and writes data to it.

    Parameters:
    - kvstore_schema (dictionary): Schema for the file store (local or remote)
    - data_shape (tuple): The shape of the data to be stored.
    - chunk_shape (tuple): The shape of the chunks in the Zarr file.
    - tstoreDataType (str): The data type of the data in the Tensorstore.
    - zarrDataType (str): The data type of the data in the Zarr file.
    - compressor (dictionary): The compression to be used for the Zarr array.
    - fillvalue (numeric scalar): The fill value to be used for the Zarr array.
    """
    schema = {
        'driver': 'zarr',
        'kvstore': kvstore_schema,
        'dtype': tstoreDataType,
        'metadata': {
            'shape': data_shape,
            'chunks': chunk_shape,
            'dtype':  zarrDataType,
            'fill_value': fillvalue,
            'compressor': compressor,
        },
        'create': True,
        'delete_existing': True,
    }
    zarr_file = ts.open(schema).result()
    return schema


def _build_schema(kvstore_schema, driver='zarr', metadata_json=""):
    """
    Build a TensorStore schema for either Zarr v2 or Zarr v3 access.
    """
    schema = {
        'driver': driver,
        'kvstore': kvstore_schema,
    }
    if metadata_json:
        schema['metadata'] = json.loads(metadata_json)
    return schema


def createZarr3(kvstore_schema, metadata_json):
    """
    Creates a new Zarr v3 array using explicit metadata.
    """
    schema = _build_schema(kvstore_schema, driver='zarr3', metadata_json=metadata_json)
    schema['create'] = True
    schema['delete_existing'] = True
    ts.open(schema).result()
    return schema


def _clone_kvstore_schema(kvstore_schema):
    """
    Return a mutable copy of a KvStore schema.
    """
    return dict(kvstore_schema)


def _normalize_kvstore_prefix(path):
    """
    Normalize a KvStore prefix so relative keys append with a single slash.
    """
    path = path or ''
    if not path:
        return ''
    return path.rstrip('/') + '/'


def _open_prefixed_kvstore(kvstore_schema, prefix=""):
    """
    Open a KvStore rooted at the requested prefix below the base schema path.
    """
    schema = _clone_kvstore_schema(kvstore_schema)
    base_path = _normalize_kvstore_prefix(schema.get('path', ''))
    prefix = str(prefix or '').strip('/')
    if prefix:
        schema['path'] = base_path + prefix + '/'
    else:
        schema['path'] = base_path
    return ts.KvStore.open(schema).result()


def kvKeyExists(kvstore_schema, key):
    """
    Return True if the specified key exists.
    """
    store = _open_prefixed_kvstore(kvstore_schema)
    result = store.read(str(key)).result()
    return result.state == 'value'


def kvPrefixExists(kvstore_schema, prefix=""):
    """
    Return True if the specified prefix contains at least one key.
    """
    store = _open_prefixed_kvstore(kvstore_schema, prefix=prefix)
    return len(store.list().result()) > 0


def kvReadBytes(kvstore_schema, key):
    """
    Read a key and return a list of byte values, or None if missing.
    """
    store = _open_prefixed_kvstore(kvstore_schema)
    result = store.read(str(key)).result()
    if result.state != 'value':
        return None
    return list(result.value)


def kvReadText(kvstore_schema, key):
    """
    Read a UTF-8 text key, or None if missing.
    """
    data = kvReadBytes(kvstore_schema, key)
    if data is None:
        return None
    return bytes(data).decode('utf-8')


def kvWriteBytes(kvstore_schema, key, value):
    """
    Write bytes to a key.
    """
    store = _open_prefixed_kvstore(kvstore_schema)
    payload = bytes(bytearray(int(x) for x in value))
    store.write(str(key), payload).result()


def kvWriteText(kvstore_schema, key, text):
    """
    Write UTF-8 text to a key.
    """
    store = _open_prefixed_kvstore(kvstore_schema)
    store.write(str(key), str(text).encode('utf-8')).result()


def kvList(kvstore_schema, prefix=""):
    """
    List all keys below the requested prefix, relative to that prefix.
    """
    store = _open_prefixed_kvstore(kvstore_schema, prefix=prefix)
    keys = store.list().result()
    return [key.decode('utf-8') if isinstance(key, bytes) else str(key) for key in keys]
            
def writeZarr (kvstore_schema, data, driver='zarr', metadata_json=""):
    """
    Writes data to a Zarr file.

    Parameters:
    - kvstore_schema (dictionary): Schema for the file store (local or remote)
    - data (numpy.ndarray): The data to write to the Zarr file.
    """
    schema = _build_schema(kvstore_schema, driver=driver, metadata_json=metadata_json)
    zarr_file = ts.open(schema).result()
    
    # Write data to the Zarr file
    zarr_file[...] = data


def writeZarrRegion(kvstore_schema, data, starts, ends, driver='zarr', metadata_json=""):
    """
    Writes a subset of data to a Zarr file.
    """
    zarr_file = ts.open(_build_schema(kvstore_schema, driver=driver, metadata_json=metadata_json)).result()
    slices = tuple(slice(int(start), int(end)) for start, end in zip(starts, ends))
    zarr_file[slices] = data


def readZarr (kvstore_schema, starts, ends, strides, driver='zarr', metadata_json=""):
    """
    Reads a subset of data from a Zarr file.

    Parameters:
    - kvstore_schema (dictionary): Schema for the file store (local or remote)
    - starts (numpy.ndarray): Array of start indices for each dimension (0-based)
    - ends (numpy.ndarray): Array of end indices for each dimension (elements 
                   at the end index will not be read)
    - strides (numpy.ndarray): Array of strides for each dimensions
    
    Returns:
    - numpy.ndarray: The subset of the data read from the Zarr file.
    """
    zarr_file = ts.open(_build_schema(kvstore_schema, driver=driver, metadata_json=metadata_json)).result()
    
    # Construct the indexing slices
    slices = tuple(slice(start, end, stride) for start, end, stride in zip(starts, ends, strides))

    # Read a subset of the data
    data = zarr_file[slices].read().result()
    
    return data


def readCompoundZarr(kvstore_schema, starts, ends, strides, field_names=None, driver='zarr'):
    """
    Read compound/structured data.

    Zarr v2 compound data is read via TensorStore field access. Zarr v3
    structured data is read via the Python zarr library because the current
    TensorStore zarr3 driver only accepts scalar string data_type metadata.
    """
    requested_fields = _normalise_field_names(field_names)

    if driver == 'zarr3':
        return readZarrWithZarrLibrary(
            kvstore_schema, starts, ends, strides,
            field_names=requested_fields)

    start_list, end_list, stride_list = _normalise_index_lists(starts, ends, strides)
    slices = tuple(slice(start, end, stride) for start, end, stride in zip(start_list, end_list, stride_list))
    result = {}
    fallback_fields = []

    for field_name in requested_fields:
        try:
            field_store = ts.open({
                'driver': driver,
                'kvstore': kvstore_schema,
                'field': field_name,
            }).result()
            field_data = field_store[slices].read().result()
            result[field_name] = _convert_field_data(field_data)
        except Exception as exc:
            error_msg = str(exc)
            if 'Unsupported zarr dtype' in error_msg:
                fallback_fields.append(field_name)
            else:
                raise exc

    if fallback_fields:
        result.update(readZarrWithZarrLibrary(
            kvstore_schema, starts, ends, strides,
            field_names=fallback_fields))

    return {field_name: result[field_name] for field_name in requested_fields}


def readZarrWithZarrLibrary(kvstore_schema, starts, ends, strides, field_names=None):
    """
    Read array data using the Python zarr library.

    This is used for structured dtypes that the TensorStore bridge cannot
    access directly, such as current Zarr v3 structured dtypes and selected
    unsupported Zarr v2 structured fields.
    """
    try:
        import zarr
    except ImportError as exc:
        raise ValueError('Reading structured data requires the "zarr" Python package to be installed.') from exc

    driver = kvstore_schema.get('driver')
    if driver == 'file':
        zarr_location = str(kvstore_schema['path'])
        zarr_array = zarr.open_array(zarr_location, mode='r')
    elif driver == 's3':
        try:
            import s3fs
        except ImportError as exc:
            raise ValueError('Reading structured data from S3 requires the "s3fs" Python package to be installed.') from exc

        bucket = kvstore_schema.get('bucket', '')
        object_path = kvstore_schema.get('path', '')
        root = f"{bucket}/{object_path.lstrip('/')}"
        s3 = s3fs.S3FileSystem()
        storage = s3fs.S3Map(root=root, s3=s3)
        zarr_array = zarr.open_array(storage, mode='r')
    else:
        raise ValueError(f"Unsupported kvstore driver '{driver}' for zarr fallback")

    start_list, end_list, stride_list = _normalise_index_lists(starts, ends, strides)
    slices = tuple(slice(start, end, stride) for start, end, stride in zip(start_list, end_list, stride_list))
    data = zarr_array[slices]

    if getattr(data.dtype, 'names', None):
        return _structured_array_to_dict(data, field_names=field_names)

    return np.asarray(data)


def _normalise_index_lists(starts, ends, strides):
    def _to_list(value):
        if isinstance(value, (int, type(None))):
            return [value]
        if isinstance(value, np.ndarray):
            return value.tolist()
        return list(value)

    start_list = _to_list(starts)
    end_list = _to_list(ends)
    stride_list = _to_list(strides)

    def _to_int(value, fallback=None):
        if value is None:
            return fallback
        return int(value)

    result = []
    for values, fallback in zip((start_list, end_list, stride_list), (0, None, 1)):
        converted = [_to_int(value, fallback) for value in values]
        result.append(converted)

    return tuple(result)


def _structured_array_to_dict(array_data, field_names=None):
    requested_fields = _normalise_field_names(field_names)
    if not requested_fields:
        requested_fields = list(array_data.dtype.names)

    result = {}
    for field_name in requested_fields:
        field_data = np.asarray(array_data[field_name])
        result[field_name] = _convert_field_data(field_data)

    return result


def _convert_field_data(field_data):
    if isinstance(field_data, np.ndarray):
        if field_data.dtype.kind in ('U', 'S', 'O'):
            return field_data.tolist()
        return field_data

    if hasattr(field_data, 'dtype') and getattr(field_data.dtype, 'kind', None) in ('U', 'S', 'O'):
        return field_data.tolist()

    return field_data


def _normalise_field_names(field_names):
    if field_names is None:
        return []

    if isinstance(field_names, str):
        return [field_names]

    try:
        values = [str(name) for name in field_names]
    except TypeError:
        return [str(field_names)]

    return [value for value in values if value]
