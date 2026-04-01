classdef TensorStoreBackedStore < ZarrStore
    %TENSORSTOREBACKEDSTORE Prototype store for future remote backends.
    %   This placeholder validates that the store abstraction can express
    %   child-address resolution independently from local filesystem paths.
    %   Metadata and listing operations remain unsupported until Phase 6.

    properties (Access = private)
        RootLocation (1,1) string
    end

    methods
        function obj = TensorStoreBackedStore(rootLocation)
            obj.RootLocation = string(rootLocation);
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

        function tf = exists(obj, key) %#ok<INUSD>
            obj.throwUnsupported("exists")
            tf = false; %#ok<NASGU>
        end

        function tf = isDirectory(obj, key) %#ok<INUSD>
            obj.throwUnsupported("isDirectory")
            tf = false; %#ok<NASGU>
        end

        function text = readText(obj, key) %#ok<INUSD>
            obj.throwUnsupported("readText")
            text = "";
        end

        function bytes = readBytes(obj, key) %#ok<INUSD>
            obj.throwUnsupported("readBytes")
            bytes = uint8.empty(0, 1);
        end

        function writeText(obj, key, text) %#ok<INUSD>
            obj.throwUnsupported("writeText")
        end

        function writeBytes(obj, key, bytes) %#ok<INUSD>
            obj.throwUnsupported("writeBytes")
        end

        function names = listChildren(obj, prefix) %#ok<INUSD>
            obj.throwUnsupported("listChildren")
            names = strings(1, 0);
        end

        function makeDir(obj, prefix) %#ok<INUSD>
            obj.throwUnsupported("makeDir")
        end
    end

    methods (Access = private)
        function throwUnsupported(obj, operation)
            error("MATLAB:ZarrStore:unsupportedOperation", ...
                "Operation ""%s"" is not supported yet for remote store ""%s"".", ...
                operation, obj.RootLocation);
        end
    end
end
