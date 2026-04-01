classdef tZarrWrite < SharedZarrTestSetup
    % Tests for zarrwrite function to write data to Zarr files in MATLAB.

    % Copyright 2025 The MathWorks, Inc.

    properties(TestParameter)
        DataType = {'double','single','int8','uint8','int16','uint16', ...
            'int32','uint32','int64','uint64','logical'}
        CompId = {'zlib','gzip','bz2','zstd'}
        ArrSizeWrite = {10, [1 10],[20 25],[10 12 5]}
    end

    methods(Test)
        function createArrayLocalDefaultSyntax(testcase,ArrSizeWrite)
            % Verify the data when creating and writing to arrays of different 
            % dimensions using zarrcreate and zarrwrite locally. The default 
            % datatype is double.;
            zarrcreate(testcase.ArrPathWrite,ArrSizeWrite);
            if isscalar(ArrSizeWrite)
                expData = (1:ArrSizeWrite)*pi;
            else
                expData = rand(ArrSizeWrite);
            end
            
            zarrwrite(testcase.ArrPathWrite,expData);

            actData = zarrread(testcase.ArrPathWrite);
            testcase.verifyEqual(actData,expData,'Failed to verify array data');
        end

        function createArrayRemoteDefaultSyntax(testcase)
            % Verify data when creating and writing to arrays of different 
            % dimensions using zarrcreate and zarrwrite to a remote location.
            
            % Move to a separate file
        end

        function createArrayLocalUserDefinedSyntax(testcase,DataType,CompId)
            % Verify the data when creating and writing to arrays with 
            % user-defined properties using zarrcreate and zarrwrite locally.
            comp.level = 5;
            fillValue = cast(-9, DataType);
            expData = cast(ones(testcase.ArrSize),DataType);
            comp.id = CompId;
            zarrcreate(testcase.ArrPathWrite,testcase.ArrSize,'ChunkSize',testcase.ChunkSize, ...
                'Compression',comp,'FillValue',fillValue,'Datatype',DataType);
            zarrwrite(testcase.ArrPathWrite,expData);

            actData = zarrread(testcase.ArrPathWrite);
            testcase.verifyEqual(actData,expData,['Failed to verify data for ' DataType ' datatype' ...
                ' with ' CompId ' compression.']);
        end

        function createArrayRemoteUserDefinedSyntax(testcase)
            % Verify data when creating and writing data to arrays with 
            % user-defined properties using zarrcreate and zarrwrite to a 
            % remote location.
        
            % Move to a separate file
        end

        function createArrayWithDefaultBloscConfig(testcase)
            % Verify data when creating and writing to a Zarr array using 
            % a default blosc compression configuration.
            comp.id = 'blosc';
            expData = randn(testcase.ArrSize);

            zarrcreate(testcase.ArrPathWrite,testcase.ArrSize,'ChunkSize', ...
                testcase.ChunkSize,'Compression',comp);
            zarrwrite(testcase.ArrPathWrite,expData);

            actData = zarrread(testcase.ArrPathWrite);
            testcase.verifyEqual(actData,expData,'Failed to verify data.');
        end

        function createArrayWithCustomBloscConfig(testcase)
            % Verify data when creating and writing to a Zarr array using 
            % custom blosc compression configuration.
            comp.id = 'blosc';
            comp.clevel = 5;
            cname = {'blosclz','lz4','lz4hc','zlib','zstd','snappy'};
            comp.shuffle = -1;
            expData = randn(testcase.ArrSize);

            for i = 1:length(cname)
                comp.cname = cname{i};
                zarrcreate(testcase.ArrPathWrite,testcase.ArrSize,'ChunkSize', ...
                    testcase.ChunkSize,'Compression',comp);
                zarrwrite(testcase.ArrPathWrite,expData);

                actData = zarrread(testcase.ArrPathWrite);
                testcase.verifyEqual(actData,expData,['Failed to verify data for ' cname(i)]);
            end
        end

        function createArrayWithDefaultCompConfig(testcase)
            % Verify data when creating and writing to a Zarr array using 
            % a default compression (other than Blosc) configuration.
            compType = {'zlib','gzip','bz2','zstd'};
            expData = randn(testcase.ArrSize);

            for i = 1:length(compType)
                comp.id = compType{i};

                zarrcreate(testcase.ArrPathWrite,testcase.ArrSize,'ChunkSize', ...
                    testcase.ChunkSize,'Compression',comp);
                zarrwrite(testcase.ArrPathWrite,expData);

                actData = zarrread(testcase.ArrPathWrite);
                testcase.verifyEqual(actData,expData,'Failed to verify data.');
            end
        end


        function tooFewInputs(testcase)
            % Verify error when too few inputs to zarrwrite are passed.
            errID = 'MATLAB:minrhs';
            testcase.verifyError(@()zarrwrite(testcase.ArrPathWrite),errID);
        end

        function invalidFilePath(testcase)
            % Verify error when an invalid file path is used.
            errID = 'MATLAB:validators:mustBeNonzeroLengthText';
            data = ones(10,10);
            testcase.verifyError(@()zarrwrite('',data),errID);
        end

        function dataDatatypeMismatch(testcase)
            % Verify error for mismatch between datatype value and datatype 
            % of data to be written with zarrwrite.
            errID = 'MATLAB:Python:PyException';
            zarrcreate(testcase.ArrPathWrite,testcase.ArrSize,"Datatype",'int8');
            data = ones(testcase.ArrSize);
            testcase.verifyError(@()zarrwrite(testcase.ArrPathWrite,data),errID);
        end

        function dataDimensionMismatch(testcase)
            % Verify error when there is a dimension mismatch at the time of 
            % writing to the array.
            errID = 'MATLAB:Zarr:sizeMismatch';
            zarrcreate(testcase.ArrPathWrite,testcase.ArrSize);
            data = ones(30,30);
            testcase.verifyError(@()zarrwrite(testcase.ArrPathWrite,data),errID);
        end

        function overwriteArray(testcase)
            % Verify data after the array data is overwritten with new
            % data.
            zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'ChunkSize',testcase.ChunkSize);
            data = ones(testcase.ArrSize);
            zarrwrite(testcase.ArrPathWrite,data);

            % Create new data
            expData = rand(testcase.ArrSize);
            zarrwrite(testcase.ArrPathWrite,expData);
            actData = zarrread(testcase.ArrPathWrite);
            testcase.verifyEqual(actData,expData,'Failed to verify array data')
        end

        function writeArrayV3(testcase)
            % Verify full writes to a Zarr v3 array.
            expData = single(reshape(1:prod(testcase.ArrSize), testcase.ArrSize));
            zarrcreate(testcase.ArrPathWrite, testcase.ArrSize, ...
                Datatype='single', ZarrFormat=3);

            zarrwrite(testcase.ArrPathWrite, expData);

            actData = zarrread(testcase.ArrPathWrite);
            testcase.verifyEqual(actData, expData, ...
                'Failed to verify full write to a Zarr v3 array.');
        end

        function partialWriteArrayV3(testcase)
            % Verify partial writes into a Zarr v3 array.
            fillValue = single(-7);
            patchData = single(reshape(1:6, [2 3]));
            expData = fillValue * ones(testcase.ArrSize, 'single');
            expData(2:3, 4:6) = patchData;

            zarrcreate(testcase.ArrPathWrite, testcase.ArrSize, ...
                Datatype='single', FillValue=fillValue, ChunkSize=[4 5], ZarrFormat=3);
            zarrwrite(testcase.ArrPathWrite, patchData, Start=[2 4]);

            actData = zarrread(testcase.ArrPathWrite);
            testcase.verifyEqual(actData, expData, ...
                'Failed to verify partial write to a Zarr v3 array.');
        end

        function partialWriteChunkEdgeV3(testcase)
            % Verify partial writes can span chunk boundaries in v3.
            zarrcreate(testcase.ArrPathWrite, [6 6], Datatype='single', ...
                ChunkSize=[3 3], ZarrFormat=3);

            patchData = single(reshape(1:9, [3 3]));
            zarrwrite(testcase.ArrPathWrite, patchData, Start=[3 3]);

            actData = zarrread(testcase.ArrPathWrite, Start=[3 3], Count=[3 3]);
            testcase.verifyEqual(actData, patchData, ...
                'Failed to verify chunk-edge partial write for a Zarr v3 array.');
        end

        function partialWriteArrayV2(testcase)
            % Verify partial writes also work for existing v2 arrays.
            zarrcreate(testcase.ArrPathWrite, testcase.ArrSize);
            zarrwrite(testcase.ArrPathWrite, ones(testcase.ArrSize));

            patchData = 2 * ones(2, 3);
            zarrwrite(testcase.ArrPathWrite, patchData, Start=[2 4]);

            actData = zarrread(testcase.ArrPathWrite, Start=[2 4], Count=[2 3]);
            testcase.verifyEqual(actData, patchData, ...
                'Failed to verify partial write for a Zarr v2 array.');
        end

        function matlabWriteV3ReadableFromPython(testcase)
            % Verify MATLAB-created default v3 data is readable through
            % the Python TensorStore layer.
            testcase.verifyV3RoundTripReadableFromPython([]);
        end

        function matlabWriteV3ZstdReadableFromPython(testcase)
            % Verify MATLAB-created zstd-compressed v3 data is readable
            % through the Python TensorStore layer.
            testcase.verifyV3RoundTripReadableFromPython(struct("id", "zstd", "level", 3));
        end

        function matlabWriteV3Crc32cReadableFromPython(testcase)
            % Verify MATLAB-created crc32c-protected v3 data is readable
            % through the Python TensorStore layer.
            compression = [ ...
                struct("name", "bytes", "configuration", struct("endian", "little")), ...
                struct("name", "crc32c", "configuration", struct())];
            testcase.verifyV3RoundTripReadableFromPython(compression);
        end

        function writeArrayV3PreservesDimensionNames(testcase)
            % Verify v3 writes preserve dimension names recorded at create time.
            dimensionNames = ["rows", "cols"];
            expData = single(reshape(1:prod(testcase.ArrSize), testcase.ArrSize));

            zarrcreate(testcase.ArrPathWrite, testcase.ArrSize, ...
                Datatype='single', DimensionNames=dimensionNames, ZarrFormat=3);
            zarrwrite(testcase.ArrPathWrite, expData);

            actInfo = zarrinfo(testcase.ArrPathWrite);
            testcase.verifyEqual(string(actInfo.dimension_names(:)), dimensionNames(:), ...
                'Failed to preserve dimension names after writing a v3 array.');
        end

        function writeToNonExistentArray(testcase)
            % Try writing to a Zarr array which has not been created yet
            errID = 'MATLAB:Zarr:invalidZarrObject';
            data = rand(10);
            testcase.verifyError(@()zarrwrite('nonExistentArray.zarr',data),errID);
        end

        function partialWriteOutOfBounds(testcase)
            % Verify out-of-bounds partial writes are rejected.
            zarrcreate(testcase.ArrPathWrite, testcase.ArrSize, ZarrFormat=3);
            data = ones(3, 3);
            testcase.verifyError(@() zarrwrite(testcase.ArrPathWrite, data, ...
                Start=[19 24]), 'MATLAB:Zarr:PartialWriteOutOfBounds');
        end
    end

    methods(Access = private)
        function verifyV3RoundTripReadableFromPython(testcase, compression)
            expData = single(reshape(1:prod(testcase.ArrSize), testcase.ArrSize));
            zarrcreate(testcase.ArrPathWrite, testcase.ArrSize, ...
                Datatype='single', Compression=compression, ZarrFormat=3);
            zarrwrite(testcase.ArrPathWrite, expData);

            actData = testcase.readV3ArrayViaPython(testcase.ArrPathWrite);
            testcase.verifyEqual(actData, expData, ...
                'Failed to verify Python/TensorStore interoperability for v3 writes.');
        end

        function data = readV3ArrayViaPython(~, filepath)
            % Read a v3 array directly through the Python TensorStore helper.
            info = zarrinfo(filepath);
            kvstore = Zarr.ZarrPy.createKVStore(false, Zarr.getFullPath(filepath));
            metadata = struct();
            metadata.zarr_format = 3;
            metadata.node_type = "array";
            metadata.shape = reshape(double(info.shape), 1, []);
            metadata.data_type = char(string(info.data_type));
            metadata.chunk_grid = info.chunk_grid;
            metadata.chunk_key_encoding = info.chunk_key_encoding;
            metadata.codecs = info.codecs;
            metadata.fill_value = info.fill_value;
            metadataJSON = jsonencode(metadata);

            shape = reshape(double(info.shape), 1, []);
            pyData = Zarr.ZarrPy.readZarr(kvstore, int64(zeros(size(shape))), ...
                int64(shape), int64(ones(size(shape))), "zarr3", metadataJSON);
            data = cast(pyData, char(ZarrDatatype.fromV3Type(string(info.data_type)).MATLABType));
        end
    end
end
