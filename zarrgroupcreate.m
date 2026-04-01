function zarrgroupcreate(filepath, options)
%ZARRGROUPCREATE Create a filesystem-backed Zarr group hierarchy.

arguments
    filepath {mustBeTextScalar, mustBeNonzeroLengthText}
    options.ZarrFormat (1,1) double {mustBeMember(options.ZarrFormat, [2 3])} = 3
end

fullPath = Zarr.getFullPath(string(filepath));
if fullPath == ""
    error("MATLAB:Zarr:invalidPath", ...
        "Unable to access path ""%s"".", filepath)
end

existingParentPath = Zarr.getExistingParentFolder(fullPath);
if existingParentPath == ""
    error("MATLAB:Zarr:invalidPath", ...
        "Unable to access path ""%s"".", filepath)
end

if fullPath ~= existingParentPath
    try
        existingParentInfo = zarrinfo(existingParentPath);
        if strcmp(existingParentInfo.node_type, 'array')
            error("MATLAB:zarrgroupcreate:invalidParentPath", ...
                "Cannot create a Zarr group inside an existing Zarr array path.");
        end
    catch err
        if ~strcmp(err.identifier, 'MATLAB:zarrinfo:invalidZarrObject')
            rethrow(err)
        end
    end
end

if fullPath == existingParentPath
    createOrValidateGroup(fullPath, options.ZarrFormat);
    return
end

newGroupsPath = extractAfter(fullPath, existingParentPath);
newGroups = split(newGroupsPath, filesep);
currentPath = existingParentPath;
for i = 1:numel(newGroups)
    groupName = newGroups(i);
    if groupName == ""
        continue
    end
    currentPath = fullfile(currentPath, groupName);
    createOrValidateGroup(currentPath, options.ZarrFormat);
end
end

function createOrValidateGroup(groupPath, zarrFormat)
store = getZarrStore(groupPath);

if store.exists('.zarray')
    error("MATLAB:zarrgroupcreate:invalidParentPath", ...
        "Cannot create a Zarr group inside an existing Zarr array path.");
end

if store.exists('.zgroup') || store.exists('zarr.json')
    currentVersion = zarrversion(groupPath);
    currentInfo = zarrinfo(groupPath);
    if ~strcmp(currentInfo.node_type, 'group')
        error("MATLAB:zarrgroupcreate:invalidParentPath", ...
            "Cannot create a Zarr group at a path already used by a Zarr array.");
    end
    if currentVersion ~= zarrFormat
        error("MATLAB:zarrgroupcreate:groupFormatMismatch", ...
            "Existing Zarr group format does not match requested ZarrFormat.");
    end
    return
end

Zarr.createGroup(groupPath, zarrFormat);
end
