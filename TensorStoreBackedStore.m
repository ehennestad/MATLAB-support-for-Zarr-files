classdef TensorStoreBackedStore < ZarrStore
    %TENSORSTOREBACKEDSTORE TensorStore-backed metadata store for S3 paths.

    properties (Access = private)
        RootLocation (1,1) string
        KVStoreSchema
    end

    methods
        function obj = TensorStoreBackedStore(rootLocation, kvStoreSchema)
            arguments
                rootLocation {mustBeTextScalar, mustBeNonzeroLengthText}
                kvStoreSchema = []
            end

            obj.RootLocation = string(rootLocation);

            if nargin >= 2 && ~isempty(kvStoreSchema)
                obj.KVStoreSchema = kvStoreSchema;
                return
            end

            Zarr.pySetup();
            [bucketName, objectPath] = Zarr.extractS3BucketNameAndPath(obj.RootLocation);
            obj.KVStoreSchema = Zarr.ZarrPy.createKVStore(true, objectPath, bucketName);
        end

        function location = resolve(obj, key)
            key = string(key);
            if key == ""
                location = obj.RootLocation;
                return
            end

            root = strip(obj.RootLocation, "right", "/");
            suffix = strip(key, "left", "/");
            location = root + "/" + suffix;
        end

        function tf = exists(obj, key)
            key = string(key);
            if key == ""
                tf = obj.tryPrefixExists("");
                return
            end

            tf = obj.tryKeyExists(key);
        end

        function tf = isDirectory(obj, key)
            key = string(key);
            tf = obj.tryPrefixExists(key);
        end

        function text = readText(obj, key)
            textValue = obj.tryReadText(key);
            if isempty(textValue)
                error("MATLAB:ZarrStore:keyNotFound", ...
                    "Key ""%s"" was not found in remote store ""%s"".", ...
                    string(key), obj.RootLocation);
            end
            text = string(textValue);
        end

        function bytes = readBytes(obj, key)
            byteValues = obj.tryReadBytes(key);
            if isempty(byteValues)
                error("MATLAB:ZarrStore:keyNotFound", ...
                    "Key ""%s"" was not found in remote store ""%s"".", ...
                    string(key), obj.RootLocation);
            end
            bytes = reshape(uint8(byteValues), [], 1);
        end

        function writeText(obj, key, text)
            try
                Zarr.ZarrPy.kvWriteText(obj.KVStoreSchema, char(string(key)), char(string(text)));
            catch ME
                obj.rethrowRemoteFailure(ME, "write text metadata")
            end
        end

        function writeBytes(obj, key, bytes)
            try
                byteList = py.list(num2cell(double(reshape(uint8(bytes), 1, []))));
                Zarr.ZarrPy.kvWriteBytes(obj.KVStoreSchema, char(string(key)), byteList);
            catch ME
                obj.rethrowRemoteFailure(ME, "write binary metadata")
            end
        end

        function names = listChildren(obj, prefix)
            keys = obj.tryList(string(prefix));
            childNames = strings(1, 0);

            for i = 1:numel(keys)
                key = strip(string(keys(i)), "left", "/");
                if key == ""
                    continue
                end

                if ~contains(key, "/")
                    if obj.isMetadataKey(key)
                        continue
                    end
                    childName = key;
                else
                    childName = extractBefore(key + "/", "/");
                end

                if childName == "" || obj.isMetadataKey(childName)
                    continue
                end

                childNames(end+1) = childName; %#ok<AGROW>
            end

            names = unique(childNames);
        end

        function makeDir(~, ~)
            % Remote backends do not require directory markers.
        end
    end

    methods (Access = private)
        function tf = tryKeyExists(obj, key)
            try
                tf = logical(Zarr.ZarrPy.kvKeyExists(obj.KVStoreSchema, char(key)));
            catch
                tf = false;
            end
        end

        function tf = tryPrefixExists(obj, prefix)
            try
                tf = logical(Zarr.ZarrPy.kvPrefixExists(obj.KVStoreSchema, char(prefix)));
            catch
                tf = false;
            end
        end

        function textValue = tryReadText(obj, key)
            try
                result = Zarr.ZarrPy.kvReadText(obj.KVStoreSchema, char(string(key)));
            catch ME
                obj.rethrowRemoteFailure(ME, "read text metadata")
            end

            if isequal(result, py.None)
                textValue = string.empty(1, 0);
            else
                textValue = string(result);
            end
        end

        function byteValues = tryReadBytes(obj, key)
            try
                result = Zarr.ZarrPy.kvReadBytes(obj.KVStoreSchema, char(string(key)));
            catch ME
                obj.rethrowRemoteFailure(ME, "read binary metadata")
            end

            if isequal(result, py.None)
                byteValues = uint8.empty(0, 1);
                return
            end

            resultCells = cell(result);
            byteValues = cellfun(@double, resultCells);
        end

        function keys = tryList(obj, prefix)
            try
                result = Zarr.ZarrPy.kvList(obj.KVStoreSchema, char(string(prefix)));
            catch ME
                obj.rethrowRemoteFailure(ME, "list children")
            end

            resultCells = cell(result);
            if isempty(resultCells)
                keys = strings(1, 0);
            else
                keys = string(cellfun(@char, resultCells, 'UniformOutput', false));
            end
        end

        function rethrowRemoteFailure(obj, err, operation)
            if strcmp(err.identifier, "MATLAB:Python:PyException")
                error("MATLAB:ZarrStore:remoteAccessFailure", ...
                    "Unable to %s for remote store ""%s"".", ...
                    operation, obj.RootLocation);
            end
            rethrow(err)
        end
    end

    methods (Static, Access = private)
        function tf = isMetadataKey(key)
            tf = any(string(key) == [".zarray", ".zgroup", ".zattrs", "zarr.json"]);
        end
    end
end
