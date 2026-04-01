function zarrwrite(filepath, data, options)
%ZARRWRITE Write to a zarr array
%   ZARRWRITE(FILEPATH, DATA) writes the MATLAB variable data (specified by
%   DATA) to the path specified by FILEPATH.
% The size of DATA must match the size of the Zarr array specified during
% creation.
%
%   ZARRWRITE(..., Start=start) writes DATA into a subset of the target
%   Zarr array starting at the one-based indices specified by START.

%   Copyright 2025 The MathWorks, Inc.

arguments
    filepath {mustBeTextScalar, mustBeNonzeroLengthText}
    data
    options.Start (1,:) {mustBeNumeric, mustBeInteger, mustBePositive} = []
end

zarrObj = Zarr(filepath);
zarrObj.write(data, options.Start)

end
