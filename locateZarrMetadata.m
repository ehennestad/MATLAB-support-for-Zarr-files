function metadata = locateZarrMetadata(filepath)
%LOCATEZARRMETADATA Locate the metadata file for a Zarr array or group.

arguments
    filepath {mustBeTextScalar, mustBeNonzeroLengthText}
end

store = getZarrStore(filepath);
metadata = struct('key', "", 'node_type', "", 'zarr_format', []);

if store.exists('.zarray')
    metadata.key = '.zarray';
    metadata.node_type = "array";
    metadata.zarr_format = 2;
elseif store.exists('.zgroup')
    metadata.key = '.zgroup';
    metadata.node_type = "group";
    metadata.zarr_format = 2;
elseif store.exists('zarr.json')
    metadata.key = 'zarr.json';
    metadata.zarr_format = 3;
    info = jsondecode(store.readText(metadata.key));
    if isfield(info, 'node_type')
        metadata.node_type = string(info.node_type);
    end
end

if metadata.key == ""
    error("MATLAB:zarrinfo:invalidZarrObject", ...
        "Invalid file path. File path must refer to a valid Zarr array or group.");
end
end
