classdef FileSystemStore < ZarrStore
    %FILESYSTEMSTORE Pure MATLAB filesystem-backed Zarr store.

    properties (Access = private)
        RootPath (1,1) string
    end

    methods
        function obj = FileSystemStore(rootPath)
            obj.RootPath = string(rootPath);
        end

        function tf = exists(obj, key)
            path = obj.resolveKey(key);
            tf = isfile(path) || isfolder(path);
        end

        function text = readText(obj, key)
            text = fileread(obj.resolveKey(key));
        end

        function bytes = readBytes(obj, key)
            path = obj.resolveKey(key);
            fid = fopen(path, 'r');
            if fid == -1
                error("MATLAB:FileSystemStore:fileOpenFailure", ...
                    "Could not open file ""%s"" for reading.", path);
            end
            closeFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
            bytes = fread(fid, inf, '*uint8');
        end

        function writeText(obj, key, text)
            obj.writeBytes(key, unicode2native(char(text), 'UTF-8'));
        end

        function writeBytes(obj, key, bytes)
            path = obj.resolveKey(key);
            obj.ensureParentFolder(path);
            fid = fopen(path, 'w');
            if fid == -1
                error("MATLAB:FileSystemStore:fileOpenFailure", ...
                    "Could not open file ""%s"" for writing.", path);
            end
            closeFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, bytes, 'uint8');
        end

        function names = listChildren(obj, prefix)
            path = obj.resolveKey(prefix);
            entries = dir(path);
            names = string({entries.name});
            names = names(~ismember(names, [".", ".."]));
        end

        function makeDir(obj, prefix)
            path = obj.resolveKey(prefix);
            if ~isfolder(path)
                mkdir(path);
            end
        end
    end

    methods (Access = private)
        function path = resolveKey(obj, key)
            key = string(key);
            if key == ""
                path = obj.RootPath;
            else
                path = fullfile(obj.RootPath, key);
            end
        end

        function ensureParentFolder(~, filePath)
            parentFolder = fileparts(filePath);
            if parentFolder ~= "" && ~isfolder(parentFolder)
                mkdir(parentFolder);
            end
        end
    end
end
