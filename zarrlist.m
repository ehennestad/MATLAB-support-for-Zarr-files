function listing = zarrlist(filepath)
%ZARRLIST List direct child Zarr arrays and groups in a filesystem group.

arguments
    filepath {mustBeTextScalar, mustBeNonzeroLengthText}
end

store = getZarrStore(filepath);
metadata = locateZarrMetadata(filepath);
if metadata.node_type ~= "group"
    error("MATLAB:zarrlist:invalidZarrGroup", ...
        "Invalid file path. File path must refer to a valid Zarr group.");
end

childNames = sort(store.listChildren(""));
listing = struct('name', {}, 'node_type', {}, 'zarr_format', {});

for i = 1:numel(childNames)
    if ~store.isDirectory(childNames(i))
        continue
    end

    try
        childPath = store.resolve(childNames(i));
        childMetadata = locateZarrMetadata(childPath);
    catch err
        if strcmp(err.identifier, 'MATLAB:zarrinfo:invalidZarrObject')
            continue
        end
        rethrow(err)
    end

    listing(end+1) = struct( ... %#ok<AGROW>
        'name', char(childNames(i)), ...
        'node_type', char(childMetadata.node_type), ...
        'zarr_format', childMetadata.zarr_format);
end
end
