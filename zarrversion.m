function version = zarrversion(filepath)
%ZARRVERSION Return the Zarr format version for an array or group.

arguments
    filepath {mustBeTextScalar, mustBeNonzeroLengthText}
end

metadata = locateZarrMetadata(filepath);
version = metadata.zarr_format;
end
