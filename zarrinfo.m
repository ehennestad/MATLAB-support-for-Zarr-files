function infoStruct = zarrinfo(filepath)
%ZARRINFO Retrieve info about the Zarr array
% %   INFO = ZARRINFO(FILEPATH) reads the metadata associated with a Zarr
% array or group located at "filepath" and return the information in a
% structure INFO, whose fields are the names of the metadata keys. 
% If "filepath" is a Zarr array (has a valid `.zarray` file), the value of
% "node_type" is "array"; if "filepath" is a Zarr group (has a valid
% `.zgroup` file), the value of the field "node_type" is "group". If you
% specify the "filepath" as a group (intermediate directory) with no
% `.zgroup` file, then the function will issue an error.

%   Copyright 2025 The MathWorks, Inc.

arguments
    filepath {mustBeTextScalar, mustBeNonzeroLengthText}
end

store = getZarrStore(filepath);
metadata = locateZarrMetadata(filepath);
infoStruct = jsondecode(store.readText(metadata.key));

if metadata.zarr_format == 2
    infoStruct.node_type = char(metadata.node_type);

    % User defined attributes are contained in .zattrs file in each array or group store
    if store.exists('.zattrs')
        userDefinedInfoStruct = readZattrs(filepath);
        userDefinedFieldNames = fieldnames(userDefinedInfoStruct);
        for i = 1:numel(userDefinedFieldNames)
            infoStruct.(userDefinedFieldNames{i}) = userDefinedInfoStruct.(userDefinedFieldNames{i});
        end
    end
else
    infoStruct = normalizeV3Info(infoStruct, filepath, store, metadata);
end

end

function infoStruct = normalizeV3Info(infoStruct, filepath, store, metadata)
if ~isfield(infoStruct, 'zarr_format') || isempty(infoStruct.zarr_format)
    infoStruct.zarr_format = metadata.zarr_format;
end

if ~isfield(infoStruct, 'node_type') || strlength(string(infoStruct.node_type)) == 0
    infoStruct.node_type = char(metadata.node_type);
else
    infoStruct.node_type = char(string(infoStruct.node_type));
end

attributes = struct();
if isfield(infoStruct, 'attributes') && ~isempty(infoStruct.attributes)
    attributes = infoStruct.attributes;
end

if store.exists('.zattrs')
    userDefinedInfoStruct = readZattrs(filepath);
    userDefinedFieldNames = fieldnames(userDefinedInfoStruct);
    for i = 1:numel(userDefinedFieldNames)
        attributes.(userDefinedFieldNames{i}) = userDefinedInfoStruct.(userDefinedFieldNames{i});
    end
end
infoStruct.attributes = attributes;

if strcmp(infoStruct.node_type, 'array')
    if ~isfield(infoStruct, 'chunk_shape')
        infoStruct.chunk_shape = [];
        if isfield(infoStruct, 'chunk_grid') && isstruct(infoStruct.chunk_grid) ...
                && isfield(infoStruct.chunk_grid, 'name') ...
                && strcmp(string(infoStruct.chunk_grid.name), "regular") ...
                && isfield(infoStruct.chunk_grid, 'configuration') ...
                && isfield(infoStruct.chunk_grid.configuration, 'chunk_shape')
            infoStruct.chunk_shape = infoStruct.chunk_grid.configuration.chunk_shape;
        end
    end

    if ~isfield(infoStruct, 'dimension_names')
        infoStruct.dimension_names = [];
    end
    
    if ~isfield(infoStruct, 'fill_value')
        infoStruct.fill_value = [];
    end

    if ~isfield(infoStruct, 'codecs')
        infoStruct.codecs = [];
    else
        infoStruct.codecs = normalizeV3Codecs(infoStruct.codecs);
    end
end
end

function codecs = normalizeV3Codecs(codecs)
if isempty(codecs)
    return
end

if isstruct(codecs)
    for idx = 1:numel(codecs)
        if ~isfield(codecs(idx), 'configuration')
            codecs(idx).configuration = struct();
        end
    end
    return
end

if iscell(codecs)
    codecStructs = repmat(struct("name", "", "configuration", struct()), 1, numel(codecs));
    for idx = 1:numel(codecs)
        codec = codecs{idx};
        codecStructs(idx).name = char(string(codec.name));
        if isfield(codec, 'configuration')
            codecStructs(idx).configuration = codec.configuration;
        else
            codecStructs(idx).configuration = struct();
        end
    end
    codecs = codecStructs;
    return
end

error("MATLAB:zarrinfo:invalidV3Codecs", ...
    "Invalid v3 codec metadata encountered.");
end
