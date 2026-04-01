function zattrsStruct = readZattrs(filepath)
%READZATTRS Helper function to read the JSON file .zattrs which contains
%user-defined attributes for a Zarr array or group.

%   Copyright 2025 The MathWorks, Inc.

zattrsStruct = struct();
store = getZarrStore(filepath);

if ~store.exists('.zattrs')
    return
end

userDefinedInfoStr = store.readText('.zattrs');

% If .zattrs file exists and is not empty
if ~isempty(userDefinedInfoStr)
    zattrsStruct = jsondecode(userDefinedInfoStr);
end
end
