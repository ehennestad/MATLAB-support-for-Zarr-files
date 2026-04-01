function store = getZarrStore(filepath)
%GETZARRSTORE Create a store object for a filesystem-backed Zarr path.

arguments
    filepath {mustBeTextScalar, mustBeNonzeroLengthText}
end

path = string(filepath);
if matlab.io.internal.vfs.validators.hasIriPrefix(path)
    error("MATLAB:ZarrStore:unsupportedLocation", ...
        "Filesystem-only operation. Remote Zarr stores are not supported here.");
end

store = FileSystemStore(path);
end
