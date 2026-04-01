classdef (Abstract) ZarrStore
    %ZARRSTORE Abstract interface for Zarr metadata and file operations.

    methods (Abstract)
        location = resolve(obj, key)
        tf = exists(obj, key)
        tf = isDirectory(obj, key)
        text = readText(obj, key)
        bytes = readBytes(obj, key)
        writeText(obj, key, text)
        writeBytes(obj, key, bytes)
        names = listChildren(obj, prefix)
        makeDir(obj, prefix)
    end
end
