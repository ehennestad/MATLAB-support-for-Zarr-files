classdef Zarr < handle
% MATLAB Gateway to Python tensorstore library functions
% An object of the 'Zarr' class is used to read and write a Zarr array.
% An instance of this class represents a Zarr array.

%   Copyright 2025 The MathWorks, Inc.

    properties(GetAccess = public, SetAccess = protected)
        Path (1,1) string
        ChunkSize
        DsetSize
        FillValue
        Datatype
        Compression
        TensorstoreSchema
        KVStoreSchema % Schema to represent the storage backend specification (local file, S3, etc)
        isRemote
    end

    methods(Static)
        function pySetup
            % Set up Python path
            
            % Python module setup and bootstrapping to MATLAB
            fullPath = mfilename('fullpath');
            zarrDirectory = fileparts(fullPath);
            zarrPyPath = fullfile(zarrDirectory, 'PythonModule');
            % Add ZarrPy to the Python search path if it is not there
            % already
            if count(py.sys.path,zarrPyPath) == 0
                insert(py.sys.path,int32(0),zarrPyPath);
            end
        end

        function zarrPy = ZarrPy()
            % Get ZarrPy Python module

            % Python will compile and cache the module after the first call
            % to import_module, so there is no harm in making this call
            % multiple times.
            zarrPy = py.importlib.import_module('ZarrPy');
        end

        function pyReloadInProcess()
            % Reload ZarrPy module after it has been modified (for
            % In-Process Python only). Need to do `clear classes` before
            % this call. For Out-of-Process Python, can just use
            % `terminate(pyenv)` instead.

            % make sure the python module is on the path
            Zarr.pySetup()

            % reload
            py.importlib.reload(Zarr.ZarrPy);
        end

        function isZarray = isZarrArray(path)
            % Given a path, determine if it is a Zarr array
            try
                metadata = locateZarrMetadata(path);
                isZarray = metadata.node_type == "array";
            catch ME
                if strcmp(ME.identifier, 'MATLAB:zarrinfo:invalidZarrObject')
                    isZarray = false;
                else
                    rethrow(ME)
                end
            end
        end

        function isZgroup = isZarrGroup(path)
            % Given a path, determine if it is a Zarr group
            try
                metadata = locateZarrMetadata(path);
                isZgroup = metadata.node_type == "group";
            catch ME
                if strcmp(ME.identifier, 'MATLAB:zarrinfo:invalidZarrObject')
                    isZgroup = false;
                else
                    rethrow(ME)
                end
            end
        end

        function newParams = processPartialReadParams(params, dims,...
                defaultValues, paramName)
            % Process the parameters for partial read (Start, Stride,
            % Count)
            arguments (Input)
                params % Start/Stride/Count parameter to be validated
                dims (1,:) double  % Zarr array dimensions
                defaultValues (1,:) 
                paramName (1,1) string 
            end

            arguments (Output)
                newParams (1,:) int64 % must be integers for tensorstore
            end
            
            if isempty(params)
                newParams = defaultValues;
                return
            end

            % Allow using a scalar value for indexing into row or column
            % datasets
            if isscalar(params) && any(dims==1) && numel(dims)==2
                newParams = defaultValues;
                % use the provided value for the non-scalar dimension
                newParams(dims~=1) = params;
                return
            end

            if numel(params) ~= numel(dims)
                error("MATLAB:Zarr:badPartialReadDimensions",...
                    "Number of elements in " +...
                    "%s must be the same "+...
                    "as the number of Zarr array dimensions.",...
                    paramName)
            end

            if any(params>dims)
                error("MATLAB:Zarr:PartialReadOutOfBounds",...
                    "Elements in %s must not exceed "+...
                    "the corresponding Zarr array dimensions.",...
                    paramName)
            end

            newParams = params;
        end

        function resolvedPath = getFullPath(path)
            % Given a path, resolves it to a full path. The trailing
            % directories do not have to exist.

            arguments (Input)
                path (1,1) string
            end

            if path == ""
                resolvedPath = pwd;
                return
            end

            resolvedPath = matlab.io.internal.filesystem.resolvePath(path).ResolvedPath;

            if resolvedPath == ""
                % If the given path does not exist, it is likely due to
                % trailing directories not existing yet. Try to resolve its
                % parent path.
                [pathToParentFolder, child, ext] = fileparts(path);

                if pathToParentFolder==path
                    % If the path was not resolved and it is the same as
                    % its parent path, then we have failed to resolve a
                    % full path. This likely indicates a problem.
                    resolvedPath = "";
                    return
                end

                % Resolve parent directory's path, and append child directory.
                resolvedParentPath = Zarr.getFullPath(pathToParentFolder);
                resolvedPath = fullfile(resolvedParentPath, child+ext);
            end
        end

        function existingParent = getExistingParentFolder(path)
            % Given a full path where some trailing directories might not yet
            % exist, determine the longest prefix path that does exist

            arguments (Input)
                path (1,1) string
            end

            if isfolder(path)
                % If the full path exists, we are done.
                existingParent = path;
                return
            end

            % Get the parent path
            [pathToParentFolder, ~, ~] = fileparts(path);
            if pathToParentFolder == path
                % If the path is not an existing folder and it is the same
                % as its parent path, we have failed to find an existing
                % parent folder. This likely indicates a problem.
                existingParent = "";
                return
            end
            % Continue recursing until an existing parent path is found
            existingParent = Zarr.getExistingParentFolder(pathToParentFolder);

        end

        function createGroup(pathToGroup, zarrFormat)
            % Create a Zarr group including creating the directory (if
            % needed) and the .zgroup file. Assumes the parent directory
            % exists
            if nargin < 2
                zarrFormat = 2;
            end

            store = getZarrStore(pathToGroup);
            store.makeDir("");

            if store.exists('.zarray') || store.exists('zarr.json')
                error("MATLAB:Zarr:invalidZarrObject",...
                    "Invalid file path. File path must refer to a valid Zarr group.");
            end

            if zarrFormat == 2
                metadataFile = '.zgroup';
                groupJSON = jsonencode(struct("zarr_format", "2"));
            else
                metadataFile = 'zarr.json';
                groupJSON = jsonencode(struct( ...
                    "attributes", struct(), ...
                    "zarr_format", 3, ...
                    "consolidated_metadata", [], ...
                    "node_type", "group"));
            end

            store.writeText(metadataFile, groupJSON);
        end

        function makeZarrGroups(existingParentPath, newGroupsPath, zarrFormat)
            % Create a hierarchy of nested Zarr groups for all directories
            % in newGroupsPath. For example, if existingParentPath is
            % "/Users/jsmith/Documents" and newGroupsPath is
            % "myfile.zarr/A/B", the following directories will be made
            % into Zgroups:
            %    /Users/jsmith/Documents/myfile.zarr/
            %    /Users/jsmith/Documents/myfile.zarr/A
            %    /Users/jsmith/Documents/myfile.zarr/A/B
            %
            % The existingParentPath and newGroupsPath should combine to
            % create an absolute path to the most nested zarr group to be
            % created
            
            arguments (Input)
                existingParentPath (1,1) string
                newGroupsPath (1,1) string
                zarrFormat (1,1) double {mustBeMember(zarrFormat, [2 3])} = 2
            end

            newGroups = split(newGroupsPath, filesep);

            for group = newGroups'
                if group == ""
                    continue
                end
                pathToNewGroup = fullfile(existingParentPath, group);
                Zarr.createGroup(pathToNewGroup, zarrFormat);
                existingParentPath = pathToNewGroup;
            end

        end

        function [bucketName, objectPath] = extractS3BucketNameAndPath(url)
            % Helper function to extract S3 bucket name and object path.
            [bucketName, objectPath, ~] = Zarr.extractS3LocationParts(url);
            bucketName = char(bucketName);
            objectPath = char(objectPath);
        end

        function [bucketName, objectPath, locationPrefix] = extractS3LocationParts(url)
            % Helper function to extract S3 bucket name, object path, and
            % path prefix shared by all descendants of the location.
            url = char(string(url));
            tokens = regexp(url, '^https://([^.]+)\.s3\.([^.]+)\.amazonaws\.com', ...
                'tokens', 'once');
            if ~isempty(tokens)
                bucketName = string(tokens{1});
                locationPrefix = "https://" + tokens{1} + ".s3." + tokens{2} + ".amazonaws.com";
                objectPath = Zarr.extractRemainingPath(url, locationPrefix);
                return
            end

            tokens = regexp(url, '^https://([^.]+)\.s3\.amazonaws\.com', ...
                'tokens', 'once');
            if ~isempty(tokens)
                bucketName = string(tokens{1});
                locationPrefix = "https://" + tokens{1} + ".s3.amazonaws.com";
                objectPath = Zarr.extractRemainingPath(url, locationPrefix);
                return
            end

            tokens = regexp(url, '^https://([^.]+)\.s3\.([^/]+)', ...
                'tokens', 'once');
            if ~isempty(tokens)
                bucketName = string(tokens{1});
                locationPrefix = "https://" + tokens{1} + ".s3." + tokens{2};
                objectPath = Zarr.extractRemainingPath(url, locationPrefix);
                return
            end

            tokens = regexp(url, '^https://s3\.amazonaws\.com/([^/]+)', ...
                'tokens', 'once');
            if ~isempty(tokens)
                bucketName = string(tokens{1});
                locationPrefix = "https://s3.amazonaws.com/" + tokens{1};
                objectPath = Zarr.extractRemainingPath(url, locationPrefix);
                return
            end

            tokens = regexp(url, '^https://s3\.([^/]+)/([^/]+)', ...
                'tokens', 'once');
            if ~isempty(tokens)
                bucketName = string(tokens{2});
                locationPrefix = "https://s3." + tokens{1} + "/" + tokens{2};
                objectPath = Zarr.extractRemainingPath(url, locationPrefix);
                return
            end

            tokens = regexp(url, '^s3://([^/]+)', 'tokens', 'once');
            if ~isempty(tokens)
                bucketName = string(tokens{1});
                locationPrefix = "s3://" + tokens{1};
                objectPath = Zarr.extractRemainingPath(url, locationPrefix);
                return
            end

            error("MATLAB:Zarr:invalidS3URL","Invalid S3 URI format.");
        end

        function tf = isRemotePath(path)
            tf = matlab.io.internal.vfs.validators.hasIriPrefix(string(path));
        end

        function parentPath = getParentPath(path)
            path = string(path);
            if Zarr.isRemotePath(path)
                [~, objectPath, locationPrefix] = Zarr.extractS3LocationParts(path);
                if objectPath == ""
                    parentPath = path;
                    return
                end

                objectParts = split(objectPath, "/");
                objectParts = objectParts(objectParts ~= "");
                if numel(objectParts) <= 1
                    parentPath = locationPrefix;
                else
                    parentPath = locationPrefix + "/" + join(objectParts(1:end-1), "/");
                end
                return
            end

            [parentPath, ~, ~] = fileparts(path);
        end

        function paths = getAncestorPaths(path)
            % Return ancestor paths from the shallowest child to the input path.
            path = string(path);
            if Zarr.isRemotePath(path)
                [~, objectPath, locationPrefix] = Zarr.extractS3LocationParts(path);
                objectParts = split(objectPath, "/");
                objectParts = objectParts(objectParts ~= "");
                paths = strings(1, 0);
                for idx = 1:numel(objectParts)
                    paths(end+1) = locationPrefix + "/" + join(objectParts(1:idx), "/"); %#ok<AGROW>
                end
                return
            end

            pathParts = split(path, filesep);
            pathParts = pathParts(pathParts ~= "");
            if startsWith(path, filesep)
                currentPath = filesep;
            else
                currentPath = "";
            end

            paths = strings(1, 0);
            for idx = 1:numel(pathParts)
                if currentPath == "" || currentPath == filesep
                    currentPath = fullfile(currentPath, pathParts(idx));
                else
                    currentPath = fullfile(currentPath, pathParts(idx));
                end
                paths(end+1) = currentPath; %#ok<AGROW>
            end
        end

        function objectPath = extractRemainingPath(url, locationPrefix)
            url = string(url);
            locationPrefix = string(locationPrefix);
            if strlength(url) <= strlength(locationPrefix)
                objectPath = "";
                return
            end

            if startsWith(url, locationPrefix + "/")
                objectPath = extractAfter(url, locationPrefix + "/");
            else
                objectPath = "";
            end
            objectPath = strip(objectPath, "/");
        end
    end

    methods 
                    
        function obj = Zarr(path)
            % Load the Python library
            Zarr.pySetup;
            
            obj.Path = path;
            obj.isRemote = matlab.io.internal.vfs.validators.hasIriPrefix(obj.Path);
            if obj.isRemote % Remote file (only S3 support at the moment)
                % Extract the S3 bucket name and path
                [bucketName, objectPath] = Zarr.extractS3BucketNameAndPath(obj.Path);
                % Create a Python dictionary for the KV store driver
                obj.KVStoreSchema = Zarr.ZarrPy.createKVStore(obj.isRemote, objectPath, bucketName);
                
            else % Local file
                % Use full path
                obj.Path = Zarr.getFullPath(path);
                if obj.Path == ""
                    % Error out if the full path could not be resolved
                    error("MATLAB:Zarr:invalidPath",...
                        "Unable to access path ""%s"".", path)
                end
                obj.KVStoreSchema = Zarr.ZarrPy.createKVStore(obj.isRemote, obj.Path);
            end
        end

        
        function data = read(obj, start, count, stride, fields)
            % Function to read the Zarr array
            if nargin < 5
                fields = strings(1, 0);
            end

            % Validate partial read parameters against array metadata.
            info = obj.getArrayInfo();
            obj.Datatype = ZarrDatatype.fromMetadataType( ...
                obj.getMetadataDatatype(info), info.zarr_format);
            numDims = numel(info.shape);
            start = Zarr.processPartialReadParams(start, info.shape,...
                ones([1,numDims]), "Start");
            stride = Zarr.processPartialReadParams(stride, info.shape,...
                ones([1,numDims]), "Stride"); 
            maxCount = (int64(info.shape') - start + 1)./stride; % has to be a row vector
            count = Zarr.processPartialReadParams(count, info.shape,...
                maxCount, "Count"); 

            if any(count>maxCount)
                error("MATLAB:Zarr:PartialReadOutOfBounds",...
                    "Requested Count in combination with other "+...
                    "parameters exceeds Zarr array dimensions.")
            end

            % Convert partial read parameters to tensorstore-style
            % indexing
            start = start - 1; % tensorstore is 0-based
            % Tensorstore uses end index instead of count
            % (it does NOT include element at the end index)
            endInds = start + stride.*count;

            if obj.Datatype.IsCompound
                requestedFields = obj.validateCompoundFieldSelection(fields);
                driver = "zarr";
                if info.zarr_format == 3
                    driver = "zarr3";
                end

                ndArrayData = Zarr.ZarrPy.readCompoundZarr( ...
                    obj.KVStoreSchema, start, endInds, stride, ...
                    py.list(cellstr(requestedFields)), driver);
                data = obj.convertCompoundData(ndArrayData, count, requestedFields);
                return
            end

            [driver, metadataJSON] = obj.getTensorStoreSpec(info);

            % Check if reading requested data might exceed available memory
            try
                zeros(count, obj.Datatype.MATLABType);
            catch ME
                if strcmp(ME.identifier, 'MATLAB:array:SizeLimitExceeded')
                    error("MATLAB:Zarr:OutOfMemory",...
                        "Reading requested data (%s %s array) "+...
                        "would exceed maximum array size preference. "+...
                        "Select a smaller subset of data to read.",...
                        join(string(count), "-by-"), obj.Datatype.MATLABType)
                end
            end

            % Read the data
            ndArrayData = Zarr.ZarrPy.readZarr(obj.KVStoreSchema,...
                start, endInds, stride, driver, metadataJSON);

            % Convert the numpy array to MATLAB array
            data = cast(ndArrayData, obj.Datatype.MATLABType);
        end

        function create(obj, dtype, data_size, chunk_size, fillvalue, compression, zarrFormat, dimensionNames)
            % Function to create the Zarr array
            if nargin < 7
                zarrFormat = 2;
            end
            if nargin < 8
                dimensionNames = strings(1, 0);
            end

            obj.DsetSize = int64(data_size);
            obj.ChunkSize = int64(chunk_size);
            obj.Datatype = ZarrDatatype.fromMATLABType(dtype);
            obj.FillValue = obj.validateFillValue(fillvalue, dtype, zarrFormat);

            if obj.isRemote
                obj.createRemote(dtype, compression, zarrFormat, dimensionNames);
                return
            end
            
            % see how much of the provided path exists already 
            existingParentPath = Zarr.getExistingParentFolder(obj.Path);

            if existingParentPath == ""
                % If no existing parent folder was found, it likely
                % indicates an issue (esp. for remote paths) - maybe the
                % path is invalid (non-existent bucket, etc.) or
                % connection/permission issue caused none of the parent
                % directories on the path to be recognized as existing
                % folders.
                error("MATLAB:Zarr:invalidPath",...
                    "Unable to access path ""%s"".", obj.Path)
            end

            obj.validateCreateParent(existingParentPath);

            if zarrFormat == 2
                % If compression is empty, it means no compression.
                if isempty(compression)
                    obj.Compression = py.None;
                else
                    obj.Compression = obj.parseCompression(compression);
                end

                obj.TensorstoreSchema = Zarr.ZarrPy.createZarr( ...
                    obj.KVStoreSchema, py.numpy.array(obj.DsetSize), ...
                    py.numpy.array(obj.ChunkSize), obj.Datatype.TensorstoreType, ...
                    obj.Datatype.ZarrType, obj.Compression, obj.FillValue);
            else
                if obj.isRemote
                    error("MATLAB:ZarrStore:unsupportedLocation", ...
                        "Filesystem-only operation. Remote Zarr stores are not supported here.");
                end

                obj.Compression = obj.parseV3Compression(compression);
                metadataJSON = obj.buildV3MetadataJSON(dimensionNames);
                obj.TensorstoreSchema = Zarr.ZarrPy.createZarr3(obj.KVStoreSchema, metadataJSON);
            end

            % if new directories were created as part of creating a
            % Zarr array, we need to make them into Zarr groups.
            newDirs = extractAfter(obj.Path, existingParentPath);
            % the last directory is a Zarr array, ones before should be
            % Zarr groups
            [newGroups, ~,~] = fileparts(newDirs);
            if newGroups ~= ""
                Zarr.makeZarrGroups(existingParentPath, newGroups, zarrFormat);
            end


        end

        function write(obj, data, start)
            % Function to write to the Zarr array
            if nargin < 3
                start = [];
            end

            info = obj.getArrayInfo();
            arrayShape = reshape(int64(info.shape), 1, []);
            dataSize = int64(obj.normalizeDataSize(size(data), double(arrayShape)));

            if isempty(start)
                isCorrectShape = isequal(arrayShape, dataSize);
            else
                start = Zarr.processPartialReadParams(start, info.shape, ...
                    ones([1, numel(arrayShape)]), "Start");
                endInds = start + dataSize - 1;
                if any(endInds > arrayShape)
                    error("MATLAB:Zarr:PartialWriteOutOfBounds", ...
                        "Requested write region exceeds Zarr array dimensions.")
                end
                isCorrectShape = true;
            end

            if ~isCorrectShape
                error("MATLAB:Zarr:sizeMismatch",...
                    "Unable to write data. Size of the data to be written must match size of the array.");
            end

            [driver, metadataJSON] = obj.getTensorStoreSpec(info);
            
            if isempty(start)
                Zarr.ZarrPy.writeZarr(obj.KVStoreSchema, data, driver, metadataJSON);
            else
                start = start - 1;
                endInds = start + dataSize;
                Zarr.ZarrPy.writeZarrRegion(obj.KVStoreSchema, data, ...
                    start, endInds, driver, metadataJSON);
            end
        end

    end

    methods (Access = protected)
        function createRemote(obj, dtype, compression, zarrFormat, dimensionNames)
            % Create a remote Zarr array using backend-aware ancestor validation.
            %#ok<INUSD>
            if zarrFormat ~= 2
                error("MATLAB:ZarrStore:unsupportedLocation", ...
                    "Remote array creation currently supports only Zarr v2.");
            end

            parentPath = Zarr.getParentPath(obj.Path);
            obj.validateRemoteCreateParent(parentPath);
            [~, ~, rootLocation] = Zarr.extractS3LocationParts(obj.Path);

            if isempty(compression)
                obj.Compression = py.None;
            else
                obj.Compression = obj.parseCompression(compression);
            end

            try
                obj.TensorstoreSchema = Zarr.ZarrPy.createZarr( ...
                    obj.KVStoreSchema, py.numpy.array(obj.DsetSize), ...
                    py.numpy.array(obj.ChunkSize), obj.Datatype.TensorstoreType, ...
                    obj.Datatype.ZarrType, obj.Compression, obj.FillValue);
            catch ME
                if strcmp(ME.identifier, "MATLAB:Python:PyException")
                    error("MATLAB:Zarr:invalidPath", ...
                        "Unable to access path ""%s"".", obj.Path)
                end
                rethrow(ME)
            end

            if parentPath ~= "" && parentPath ~= rootLocation
                zarrgroupcreate(parentPath, ZarrFormat=zarrFormat);
            end
        end

        function info = getArrayInfo(obj)
            % Load array metadata and normalize errors to the Zarr API.
            try
                info = zarrinfo(obj.Path);
            catch ME
                if any(strcmp(ME.identifier, {'MATLAB:zarrinfo:invalidZarrObject', ...
                        'MATLAB:ZarrStore:unsupportedOperation', ...
                        'MATLAB:ZarrStore:unsupportedLocation'}))
                    error("MATLAB:Zarr:invalidZarrObject",...
                        "Invalid file path. File path must refer to a valid Zarr array.");
                end
                rethrow(ME)
            end

            if ~isfield(info, 'node_type') || ~strcmp(string(info.node_type), "array")
                error("MATLAB:Zarr:invalidZarrObject",...
                    "Invalid file path. File path must refer to a valid Zarr array.");
            end
        end

        function [driver, metadataJSON] = getTensorStoreSpec(~, info)
            % Build the TensorStore spec from normalized metadata.
            metadataJSON = "";

            if info.zarr_format == 2
                driver = "zarr";
                return
            end

            driver = "zarr3";
            metadata = struct();
            metadata.zarr_format = 3;
            metadata.node_type = "array";
            metadata.shape = reshape(info.shape, 1, []);
            metadata.data_type = char(string(info.data_type));
            metadata.chunk_grid = info.chunk_grid;
            metadata.chunk_key_encoding = info.chunk_key_encoding;
            metadata.codecs = info.codecs;
            metadata.fill_value = info.fill_value;

            if isfield(info, 'attributes') && ~isempty(info.attributes)
                metadata.attributes = info.attributes;
            end

            if isfield(info, 'dimension_names') && ~isempty(info.dimension_names)
                metadata.dimension_names = info.dimension_names;
            end

            metadataJSON = jsonencode(metadata);
            metadataJSON = Zarr.restoreSpecialV3AttributeNames(metadataJSON);
        end

        function dtype = getMetadataDatatype(~, info)
            % Return the dtype field used by the current Zarr metadata version.
            if info.zarr_format == 2
                dtype = info.dtype;
            else
                dtype = info.data_type;
            end
        end

        function requestedFields = validateCompoundFieldSelection(obj, fields)
            % Normalize and validate the requested compound field names.
            compoundFields = [obj.Datatype.CompoundFields{:}];
            availableFields = string(arrayfun(@(f) char(f.name), compoundFields, ...
                'UniformOutput', false));

            if isempty(fields)
                requestedFields = availableFields;
                return
            end

            if ischar(fields) || (isstring(fields) && isscalar(fields))
                requestedFields = string(fields);
            elseif isstring(fields)
                requestedFields = reshape(fields, 1, []);
            elseif iscell(fields)
                try
                    requestedFields = string(fields);
                catch
                    error("MATLAB:zarrread:invalidFields", ...
                        "Specify Fields as text values naming compound fields.");
                end
                requestedFields = reshape(requestedFields, 1, []);
            else
                error("MATLAB:zarrread:invalidFields", ...
                    "Specify Fields as text values naming compound fields.");
            end

            if any(strlength(requestedFields) == 0)
                error("MATLAB:zarrread:invalidFields", ...
                    "Fields must contain non-empty field names.");
            end

            if numel(unique(requestedFields)) ~= numel(requestedFields)
                error("MATLAB:zarrread:duplicateFields", ...
                    "Fields must not contain duplicate compound field names.");
            end

            if ~all(ismember(requestedFields, availableFields))
                missingFields = requestedFields(~ismember(requestedFields, availableFields));
                error("MATLAB:zarrread:unknownField", ...
                    "Unknown compound field requested: %s.", join(missingFields, ", "));
            end
        end

        function data = convertCompoundData(obj, pythonDict, count, requestedFields)
            % Convert Python dictionary containing compound data to a MATLAB struct array.
            if nargin < 4
                requestedFields = strings(1, 0);
            end

            if ~(isa(pythonDict, 'py.dict') || isstruct(pythonDict))
                error("MATLAB:Zarr:ExpectedDictionary", ...
                    "Expected structured data to be present as a dictionary.");
            end

            if isempty(requestedFields)
                requestedFields = obj.validateCompoundFieldSelection(strings(1, 0));
            end

            compoundFields = obj.getRequestedCompoundFields(requestedFields);
            unsupportedSubarrays = arrayfun(@(f) ~isempty(f.subarrayShape), compoundFields);
            if any(unsupportedSubarrays)
                error("MATLAB:Zarr:unsupportedCompoundField", ...
                    "Compound fields with subarray shapes are not currently supported.");
            end

            if isempty(compoundFields)
                data = struct([]);
                return
            end

            targetShape = reshape(double(count), 1, []);
            if isempty(targetShape)
                targetShape = [1, 1];
            elseif numel(targetShape) == 1
                targetShape = [targetShape, 1];
            end

            fieldNames = cellstr(requestedFields);
            flattenedValues = cell(1, numel(fieldNames));
            for idx = 1:numel(fieldNames)
                pyValue = obj.getCompoundFieldValue(pythonDict, fieldNames{idx});
                flattenedValues{idx} = obj.convertCompoundFieldData( ...
                    pyValue, compoundFields(idx).matlabType, targetShape);
            end

            numElements = prod(targetShape);
            templateStruct = cell2struct(cell(1, numel(fieldNames)), fieldNames, 2);
            structArray(1:numElements) = templateStruct; %#ok<AGROW>

            for elemIdx = 1:numElements
                for fieldIdx = 1:numel(fieldNames)
                    fieldValues = flattenedValues{fieldIdx};
                    structArray(elemIdx).(fieldNames{fieldIdx}) = fieldValues(elemIdx);
                end
            end

            data = reshape(structArray, targetShape);
            if numElements == 1
                data = data(1);
            end
        end

        function matlabData = convertCompoundFieldData(~, pythonFieldData, matlabType, targetShape)
            % Convert an individual compound field from Python to MATLAB.
            matlabType = string(matlabType);
            if matlabType == ""
                matlabType = "double";
            end

            targetShape = reshape(double(targetShape), 1, []);
            if numel(targetShape) == 1
                targetShape = [targetShape, 1];
            end

            if matlabType == "string"
                if isa(pythonFieldData, 'py.list') || isa(pythonFieldData, 'py.tuple')
                    cellValues = cell(pythonFieldData);
                elseif isa(pythonFieldData, 'py.numpy.ndarray') && py.hasattr(pythonFieldData, 'tolist')
                    cellValues = cell(py.list(pythonFieldData.tolist()));
                else
                    cellValues = {char(py.str(pythonFieldData))};
                end

                matlabData = reshape(string(cellValues), targetShape);
                return
            end

            if isa(pythonFieldData, 'py.numpy.ndarray')
                try
                    flags = pythonFieldData.flags;
                    if ~logical(py.getattr(flags, 'c_contiguous'))
                        pythonFieldData = py.numpy.ascontiguousarray(pythonFieldData);
                    end
                catch
                    % Let MATLAB try conversion directly if contiguity inspection fails.
                end

                % MATLAB does not reliably cast integer/float NumPy ndarrays
                % directly. Convert through float64 first, then cast back.
                pythonFieldData = py.numpy.asarray( ...
                    pythonFieldData, pyargs('dtype', py.numpy.float64));
                numericValues = double(pythonFieldData);
            elseif isa(pythonFieldData, 'py.list') || isa(pythonFieldData, 'py.tuple')
                cellValues = cell(pythonFieldData);
                numericValues = zeros(numel(cellValues), 1);
                for idx = 1:numel(cellValues)
                    numericValues(idx) = double(cellValues{idx});
                end
            else
                numericValues = double(pythonFieldData);
            end

            if matlabType == "logical"
                matlabData = reshape(logical(numericValues), targetShape);
            else
                matlabData = reshape(cast(numericValues, char(matlabType)), targetShape);
            end
        end

        function compoundFields = getRequestedCompoundFields(obj, requestedFields)
            % Return compound field metadata in the requested order.
            allFields = [obj.Datatype.CompoundFields{:}];
            allFieldNames = string(arrayfun(@(f) char(f.name), allFields, ...
                'UniformOutput', false));
            compoundFields = repmat(allFields(1), 1, numel(requestedFields));
            for idx = 1:numel(requestedFields)
                fieldIdx = find(allFieldNames == requestedFields(idx), 1);
                compoundFields(idx) = allFields(fieldIdx);
            end
        end

        function pyValue = getCompoundFieldValue(~, pythonDict, fieldName)
            % Read a single field value from a Python or MATLAB dictionary.
            if isa(pythonDict, 'py.dict')
                pyValue = pythonDict.get(py.str(fieldName));
                if isa(pyValue, 'py.NoneType')
                    error("MATLAB:zarrread:unknownField", ...
                        "Compound field ""%s"" was not returned by the backend reader.", fieldName);
                end
                return
            end

            if ~isfield(pythonDict, fieldName)
                error("MATLAB:zarrread:unknownField", ...
                    "Compound field ""%s"" was not returned by the backend reader.", fieldName);
            end

            pyValue = pythonDict.(fieldName);
        end

        function compression = parseCompression(~,compression)
            % Helper function to validate and parse the compression struct.

            % The compression struct should have an 'id' field.
            if ~isfield(compression, 'id')
                error("MATLAB:Zarr:missingCompressionID",...
                    "Compression structure must contain an id field. Specify compression id as ""zlib"", ""gzip"", ""blosc"", ""bz2"", or ""zstd"".");
            end
            switch(compression.id)
                case {"zlib", "gzip", "bz2", "zstd"}
                    % Only 'level' optional field for these compressions
                    if ~isfield(compression, 'level')
                        compression.level = 1;
                    end
                case "blosc"
                    % Fields for blosc compression
                    if ~isfield(compression, 'cname')
                        compression.cname = 'lz4';
                    end
                    if ~isfield(compression, 'clevel')
                        compression.clevel = 5;
                    end
                    if ~isfield(compression, 'shuffle')
                        compression.shuffle = -1;
                    end
                otherwise
                    error("MATLAB:Zarr:invalidCompressionID",...
                        "Invalid compression id. Specify compression id as ""zlib"", ""gzip"", ""blosc"", ""bz2"", or ""zstd"".");
            end
        end

        function fillValue = validateFillValue(~, fillvalue, dtype, zarrFormat)
            % Validate and normalize the fill value for the requested format.
            if isempty(fillvalue)
                if zarrFormat == 2
                    fillValue = py.None;
                else
                    fillValue = cast(0, dtype);
                end
                return
            end

            if ~isscalar(fillvalue) || ~isa(fillvalue, dtype)
                error("MATLAB:zarrcreate:invalidFillValueType",...
                    "Fill value must have the same data type (""%s"") as the Zarr array.",...
                    dtype)
            end

            fillValue = fillvalue;
        end

        function validateCreateParent(obj, existingParentPath)
            % Prevent creating arrays inside incompatible existing Zarr nodes.
            if obj.Path == existingParentPath
                return
            end

            try
                parentInfo = zarrinfo(existingParentPath);
            catch ME
                if strcmp(ME.identifier, 'MATLAB:zarrinfo:invalidZarrObject')
                    return
                end
                rethrow(ME)
            end

            if strcmp(string(parentInfo.node_type), "array")
                error("MATLAB:Zarr:invalidParentPath", ...
                    "Cannot create a Zarr array inside an existing Zarr array path.");
            end
        end

        function validateRemoteCreateParent(~, parentPath)
            % Prevent creating remote arrays inside existing remote arrays.
            if parentPath == ""
                return
            end

            remoteParents = Zarr.getAncestorPaths(parentPath);
            for idx = 1:numel(remoteParents)
                try
                    parentInfo = zarrinfo(remoteParents(idx));
                catch ME
                    if strcmp(ME.identifier, 'MATLAB:zarrinfo:invalidZarrObject')
                        continue
                    end
                    rethrow(ME)
                end

                if strcmp(string(parentInfo.node_type), "array")
                    error("MATLAB:Zarr:invalidParentPath", ...
                        "Cannot create a Zarr array inside an existing Zarr array path.");
                end
            end
        end

        function dataSize = normalizeDataSize(~, inputSize, arrayShape)
            % Normalize MATLAB size output so it can be compared with Zarr shapes.
            dataSize = reshape(double(inputSize), 1, []);
            targetDims = numel(arrayShape);

            if numel(dataSize) < targetDims
                dataSize(end+1:targetDims) = 1;
            elseif numel(dataSize) > targetDims
                extraDims = dataSize(targetDims+1:end);
                if any(extraDims ~= 1)
                    return
                end
                dataSize = dataSize(1:targetDims);
            end
        end

        function codecs = parseV3Compression(obj, compression)
            % Validate the supported v3 codec chain.
            if isempty(compression)
                codecs = obj.getDefaultV3Codecs();
                return
            end

            if isfield(compression, 'id')
                compression = obj.mapLegacyCompressionToV3Codecs(compression);
            end

            if ~(isstruct(compression) && all(isfield(compression, 'name')))
                error("MATLAB:Zarr:unsupportedV3CodecChain", ...
                    "Supported Zarr v3 codec chains use a little-endian bytes codec followed by gzip, zstd, or crc32c.");
            end

            codecs = obj.validateV3CodecChain(compression);
        end

        function codecs = mapLegacyCompressionToV3Codecs(~, compression)
            % Support a small v3-compatible subset of the legacy Compression syntax.
            if ~isfield(compression, 'id')
                error("MATLAB:Zarr:unsupportedV3CodecChain", ...
                    "Supported Zarr v3 codec chains use a little-endian bytes codec followed by gzip, zstd, or crc32c.");
            end

            codecName = string(compression.id);
            if ~any(codecName == ["gzip", "zstd"])
                error("MATLAB:Zarr:unsupportedV3CodecChain", ...
                    "Legacy v3 Compression syntax supports only gzip or zstd.");
            end

            level = 1;
            if isfield(compression, 'level')
                level = compression.level;
            end

            codecs = [ ...
                struct("name", "bytes", "configuration", struct("endian", "little")), ...
                struct("name", char(codecName), "configuration", struct("level", level))];
        end

        function codecs = validateV3CodecChain(~, codecs)
            % Normalize and validate the supported v3 codec chain.
            if numel(codecs) ~= 2
                error("MATLAB:Zarr:unsupportedV3CodecChain", ...
                    "Supported Zarr v3 codec chains must contain exactly two codecs.");
            end

            bytesCodec = Zarr.validateV3BytesCodec(codecs(1));
            dataCodec = Zarr.validateV3PayloadCodec(codecs(2));

            codecs = [bytesCodec, dataCodec];
        end

        function codecs = getDefaultV3Codecs(~)
            % Return the portable default codec chain for Zarr v3 arrays.
            codecs = [ ...
                struct("name", "bytes", "configuration", struct("endian", "little")), ...
                struct("name", "gzip", "configuration", struct("level", 1))];
        end

        function metadataJSON = buildV3MetadataJSON(obj, dimensionNames)
            % Build a TensorStore-compatible metadata document for Zarr v3 creation.
            if nargin < 2
                dimensionNames = strings(1, 0);
            end

            metadata = struct();
            metadata.zarr_format = 3;
            metadata.node_type = "array";
            metadata.shape = reshape(double(obj.DsetSize), 1, []);
            metadata.data_type = char(obj.Datatype.ZarrV3Type);
            metadata.chunk_grid = struct( ...
                "name", "regular", ...
                "configuration", struct("chunk_shape", reshape(double(obj.ChunkSize), 1, [])));
            metadata.chunk_key_encoding = struct( ...
                "name", "default", ...
                "configuration", struct("separator", "/"));
            metadata.fill_value = obj.FillValue;
            metadata.codecs = obj.Compression;

            if ~isempty(dimensionNames)
                metadata.dimension_names = cellstr(reshape(string(dimensionNames), 1, []));
            end

            metadataJSON = jsonencode(metadata);
        end

 
    end

    methods(Static, Access = private)
        function metadataJSON = restoreSpecialV3AttributeNames(metadataJSON)
            % Restore v3 attribute keys that MATLAB mangles during jsondecode/jsonencode.
            metadataJSON = strrep(metadataJSON, '"x_ARRAY_DIMENSIONS"', '"_ARRAY_DIMENSIONS"');
        end

        function codec = validateV3BytesCodec(codec)
            if string(codec.name) ~= "bytes"
                error("MATLAB:Zarr:unsupportedV3CodecChain", ...
                    "The first Zarr v3 codec must be the bytes codec.");
            end

            if ~isfield(codec, 'configuration') || ~isfield(codec.configuration, 'endian')
                codec.configuration = struct("endian", "little");
            end

            if string(codec.configuration.endian) ~= "little"
                error("MATLAB:Zarr:unsupportedV3CodecChain", ...
                    "Only little-endian Zarr v3 bytes codecs are supported.");
            end
        end

        function codec = validateV3PayloadCodec(codec)
            codecName = string(codec.name);

            switch codecName
                case {"gzip", "zstd"}
                    if ~isfield(codec, 'configuration') || ~isfield(codec.configuration, 'level')
                        codec.configuration = struct("level", 1);
                    end
                    level = codec.configuration.level;
                    if ~(isscalar(level) && isnumeric(level) && isfinite(level) && level == fix(level))
                        error("MATLAB:Zarr:unsupportedV3CodecChain", ...
                            "The %s codec level must be a finite integer scalar.", codecName);
                    end

                    if codecName == "gzip" && (level < 0 || level > 9)
                        error("MATLAB:Zarr:unsupportedV3CodecChain", ...
                            "The gzip codec level must be in the range [0, 9].");
                    end

                    if codecName == "zstd" && (level < -131072 || level > 22)
                        error("MATLAB:Zarr:unsupportedV3CodecChain", ...
                            "The zstd codec level must be in the range [-131072, 22].");
                    end

                case "crc32c"
                    if isfield(codec, 'configuration') && ~isempty(fieldnames(codec.configuration))
                        error("MATLAB:Zarr:unsupportedV3CodecChain", ...
                            "The crc32c codec does not accept configuration parameters.");
                    end
                    if ~isfield(codec, 'configuration')
                        codec.configuration = struct();
                    end

                otherwise
                    error("MATLAB:Zarr:unsupportedV3CodecChain", ...
                        "Supported Zarr v3 payload codecs are gzip, zstd, and crc32c.");
            end
        end
    end

end
