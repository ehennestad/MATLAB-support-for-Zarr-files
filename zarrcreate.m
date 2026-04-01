function zarrcreate(filepath, datasize, options)
%ZARRCREATE Create Zarr array.
%   ZARRCREATE(FILEPATH, DATASIZE, Name=Value) creates a Zarr
%   array at the path specified by FILEPATH and of the dimensions specified
%   by DATASIZE.
% If FILEPATH is a full path name, the function creates all intermediate
% directories that do not already exist and makes them into Zarr groups. If
% FILEPATH exists already, the contents are overwritten.
% 
% Name - Value Pairs
% ------------------
%     Datatype                - One of "double", "single", "uint64",
%                               "int64", "uint32", "int32", "uint16",
%                               "int16", "uint8", or "int8".
%                               Defaults to "double".
% 
%     ChunkSize               - Defines chunking layout specified as an
%                               array of integers.
%                               Default is [], which specifies no chunking.
% 
%     FillValue               - Defines the Fill value for numeric arrays.
%                               Default is [], which specifies no fill
%                               value.
% 
%     Compression             - Primary compression codec used to compress
%                               the Zarr array. By default, no compression
%                               is applied. To enable compression, specify
%                               a struct containing an "id" field. The
%                               fields for the struct are as follows:
%                               "id"    - The accepted values are "zlib", "gzip",
%                                         "blosc", "bz2", or "zstd".                               
%                               Optional Fields:
%                                 "level" - Compression level, specified as
%                                           an integer.
%                                           Valid for all but "blosc"
%                                           compression. The default value
%                                           is 1. The accepted integer
%                                           values for different
%                                           compressions are: zlib - [0, 9]
%                                           gzip - [0, 9] bz2  - [1, 9]
%                                           zstd - [-131072, 22]
%                                 "cname" - Valid only for "blosc"
%                                           compression. Name of
%                                           compression scheme for blosc
%                                           compression, specified as one
%                                           of these values: "blosclz",
%                                           "lz4", "lz4hc", "snappy",
%                                           "zlib", "zstd". "zstd" is the
%                                           same scheme as "lz4".
%                                 "clevel" - Valid only for "blosc"
%                                            compression. Compression level
%                                            for blosc compression,
%                                            specified as an integer in the
%                                            range [0, 9]. The default
%                                            value is 5.
%                                 "shuffle" - Valid only for "blosc"
%                                             compression.
%                                             Method for rearranging input
%                                             data for blosc compression,
%                                             specified as one of these
%                                             values:
%                                                -1 - Automatic shuffle.
%                                                The function performs a
%                                                bit-wise shuffle
%                                                     if the element size
%                                                     is one byte and
%                                                     otherwise performs a
%                                                     byte-wise shuffle.
%                                                 0 - No shuffle. 1 -
%                                                 Byte-wise shuffle. 2 -
%                                                 Bit-wise shuffle.
%                                             The default value is 0.
%                                 "blocksize" - Valid only for "blosc"
%                                               compression.
%                                               Block size for blosc
%                                               compression, specified as a
%                                               nonnegative integer or inf.
%                                               The default value is 0.
%
%     DimensionNames          - Names for each array dimension, specified
%                               as a string array, cell array of character
%                               vectors, or character vector. Supported
%                               only for Zarr v3 arrays.

%   Copyright 2025 The MathWorks, Inc.

arguments
    filepath {mustBeTextScalar, mustBeNonempty}
    datasize (1,:) double {mustBeFinite, mustBePositive, mustBeNonempty}
    options.ChunkSize (1,:) double {mustBeFinite, mustBePositive} = datasize
    options.Datatype {mustBeTextScalar, mustBeNonempty} = 'double'
    options.FillValue {mustBeNumericOrLogical} = []
    options.Compression {mustBeStructOrEmpty} = []
    options.DimensionNames = []
    options.ZarrFormat (1,1) double {mustBeMember(options.ZarrFormat, [2 3])} = 2
end

% Dimensionality of the dataset and the chunk size must be the same
if any(size(datasize) ~= size(options.ChunkSize))
    error("MATLAB:zarrcreate:chunkDimsMismatch",...
        "Invalid chunk size. Chunk size must have the same number of dimensions as Zarr array size.");
end

if any(options.ChunkSize > datasize)
    error("MATLAB:zarrcreate:chunkSizeGreater",...
        "Invalid chunk size. Each entry of ChunkSize must be less than or equal to the corresponding entry of Zarr array size.");
end
if isscalar(datasize)
    datasize = [1 datasize];
    options.ChunkSize = [1 options.ChunkSize];
end

dimensionNames = normalizeDimensionNames(options.DimensionNames, numel(datasize), options.ZarrFormat);

zarrObj = Zarr(filepath);
zarrObj.create(options.Datatype, datasize, options.ChunkSize, ...
    options.FillValue, options.Compression, options.ZarrFormat, dimensionNames)

end

% Input validation for compression
function mustBeStructOrEmpty(compression)
if ~(isstruct(compression) || isempty(compression))
    error("MATLAB:zarrcreate:invalidCompression",...
        "Invalid data type. Specify Compression as a structure.");
end
end

function dimensionNames = normalizeDimensionNames(dimensionNames, numDims, zarrFormat)
if isempty(dimensionNames)
    dimensionNames = strings(1, 0);
    return
end

if zarrFormat ~= 3
    error("MATLAB:zarrcreate:dimensionNamesRequireV3", ...
        "DimensionNames are supported only for Zarr v3 arrays.");
end

if ischar(dimensionNames)
    dimensionNames = string({dimensionNames});
elseif iscellstr(dimensionNames)
    dimensionNames = string(dimensionNames);
elseif isstring(dimensionNames)
    % already normalized below
else
    error("MATLAB:zarrcreate:invalidDimensionNamesType", ...
        "DimensionNames must be a string array, character vector, or cell array of character vectors.");
end

dimensionNames = reshape(string(dimensionNames), 1, []);

if any(strlength(dimensionNames) == 0)
    error("MATLAB:zarrcreate:emptyDimensionName", ...
        "DimensionNames must contain non-empty text values.");
end

if numel(dimensionNames) ~= numDims
    error("MATLAB:zarrcreate:dimensionNamesMismatch", ...
        "DimensionNames must contain one name for each Zarr array dimension.");
end

if numel(unique(dimensionNames)) ~= numel(dimensionNames)
    error("MATLAB:zarrcreate:duplicateDimensionNames", ...
        "DimensionNames must be unique.");
end
end
