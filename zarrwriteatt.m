function zarrwriteatt(filepath, attname, attvalue)
%ZARRWRITEATT Write custom Zarr attributes
%   ZARRWRITEATT(FILEPATH,ATTNAME,ATTVALUE) Write the attribute named
%   ATTNAME with the value ATTVALUE to the Zarr array or group located at
%   FILEPATH.
% For Zarr v2, attributes are stored in the .zattrs file. For Zarr v3,
% attributes are stored inline in zarr.json. The attribute is written only
% if valid Zarr metadata exists at FILEPATH. Otherwise, the function
% issues an error.

%   Copyright 2025 The MathWorks, Inc.

arguments
    filepath {mustBeTextScalar, mustBeNonzeroLengthText}
    attname {mustBeTextScalar, mustBeNonzeroLengthText}
    attvalue
end

store = getZarrStore(filepath);

try
    metadata = locateZarrMetadata(filepath);
catch err
    if strcmp(err.identifier, 'MATLAB:zarrinfo:invalidZarrObject')
        error("MATLAB:zarrwriteatt:invalidZarrObject", ...
            "Invalid file path. File path must refer to a valid Zarr array or group.");
    end
    rethrow(err)
end

if metadata.zarr_format == 3
    metadataStruct = jsondecode(store.readText(metadata.key));
    if ~isfield(metadataStruct, 'attributes') || isempty(metadataStruct.attributes)
        metadataStruct.attributes = struct();
    end
    metadataStruct.attributes.(attname) = attvalue;
    updatedJsonStr = jsonencode(metadataStruct);
    targetKey = metadata.key;
else
    % If .zattrs file exists already, append to it. If not, create the file and
    % write to it.
    if store.exists('.zattrs')
        userDefinedInfoStruct = readZattrs(filepath);
    else
        userDefinedInfoStruct = struct();
    end
    userDefinedInfoStruct.(attname) = attvalue;

    % Encode the updated structure back to JSON
    updatedJsonStr = jsonencode(userDefinedInfoStruct);
    targetKey = '.zattrs';
end

% Write the updated JSON data back to the file
try
    store.writeText(targetKey, updatedJsonStr);
catch err
    if strcmp(err.identifier, 'MATLAB:FileSystemStore:fileOpenFailure')
        error("MATLAB:zarrwriteatt:fileOpenFailure",...
            "Could not open file ""%s"" for writing.", filepath);
    end
    rethrow(err)
end

end
