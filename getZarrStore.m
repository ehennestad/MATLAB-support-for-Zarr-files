function store = getZarrStore(filepath)
%GETZARRSTORE Create a store object for a Zarr path.

arguments
    filepath {mustBeTextScalar, mustBeNonzeroLengthText}
end

path = string(filepath);
if matlab.io.internal.vfs.validators.hasIriPrefix(path)
    store = TensorStoreBackedStore(path);
    return
end

store = FileSystemStore(path);
end
