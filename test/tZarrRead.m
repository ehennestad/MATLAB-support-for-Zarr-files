classdef tZarrRead < matlab.unittest.TestCase
    % Tests for zarrread function to read data from Zarr files in MATLAB.

    % Copyright 2025 The MathWorks, Inc.

    properties(Constant)
        % Path for read functions
        GrpPathRead = "dataFiles/grp_v2"
        ArrPathRead = "dataFiles/grp_v2/arr_v2"
        ArrPathReadSmall = "dataFiles/grp_v2/smallArr"
        ArrPathReadVector = "dataFiles/grp_v2/vectorData"

        ExpData = load(fullfile(pwd,"dataFiles","expZarrArrData.mat"))
    end

    properties
        ArrPathReadV3
        ArrPathReadV3Fill
    end

    methods(TestClassSetup)
        function addSrcCodePath(testcase)
            % Add source code path before running the tests
            import matlab.unittest.fixtures.PathFixture
            testcase.applyFixture(PathFixture(fullfile('..'),'IncludeSubfolders',true))
        end

        function setupFixtures(testcase)
            % Create runtime v3 fixtures under a temporary directory.
            runtimeRoot = string(tempname);
            mkdir(runtimeRoot);
            testcase.addTeardown(@()rmdir(runtimeRoot, 's'));

            testcase.ArrPathReadV3 = fullfile(runtimeRoot, "arr_v3");
            testcase.ArrPathReadV3Fill = fullfile(runtimeRoot, "arr_v3_fill");
            testcase.createV3ReadFixtures();
        end
    end

    methods(Test)
        function verifyArrayData(testcase)
            % Verify array data using zarrread function.
            actArrData = zarrread(testcase.ArrPathRead);
            expArrData = testcase.ExpData.arr_v2;
            testcase.verifyEqual(actArrData,expArrData,'Failed to verify array data.');
        end

        function verifyPartialArrayData(testcase)
            % Verify array data using zarrread function with Start/Stride/Count.

            % The full data in the small array is
            %
            % 1    4    7   10
            % 2    5    8   11
            % 3    6    9   12
            zpath = testcase.ArrPathReadSmall;

            % Start
            actData = zarrread(zpath, Start=[2, 3]);
            expData = [8, 11; 9, 12];
            testcase.verifyEqual(actData,expData,...
                'Failed to verify reading with Start.');

            % Count
            actData = zarrread(zpath, Count=[2, 1]);
            expData = [1;2];
            testcase.verifyEqual(actData,expData,...
                'Failed to verify reading with Count.');

            % Stride
            actData = zarrread(zpath, Stride=[3, 2]);
            expData = [1, 7];
            testcase.verifyEqual(actData,expData,...
                'Failed to verify reading with Stride.');

            % Start, Stride, and Count
            actData = zarrread(zpath,...
                Start=[2, 1], Stride=[1, 2], Count=[1, 2]);
            expData = [2, 8];
            testcase.verifyEqual(actData,expData,...
                'Failed to verify reading with Start, Stride, and Count.');
        end

        function verifyPartialVectorData(testcase)
            % Verify that specifying a scalar value for Start/Stride/Count
            % for vector datasets works as expected

            zpath = testcase.ArrPathReadVector; % data is 1:10

            expData = [2,5];
            actData = zarrread(zpath, Start=2, Stride=3, Count=2);
            testcase.verifyEqual(actData,expData,...
                'Failed to verify using scalar Start, Stride, and Count.');
        end

        function verifyArrayDataRelativePath(testcase)
            % Verify array data if the input is using relative path to the
            % array.
            inpPath = fullfile('..','test',testcase.ArrPathRead);
            actArrData = zarrread(inpPath);
            expArrData = testcase.ExpData.arr_v2;
            testcase.verifyEqual(actArrData,expArrData,['Failed to verify array ' ...
                'data with relative path.']);
        end

        function verifyArrReadV3(testcase)
            % Verify full read from a Zarr v3 array.
            expData = testcase.getExpectedV3Data();
            actData = zarrread(testcase.ArrPathReadV3);
            testcase.verifyEqual(actData, expData, ...
                'Failed to verify full read from a Zarr v3 array.');
        end

        function verifyPartialArrayDataV3(testcase)
            % Verify partial reads from a Zarr v3 array.
            expData = testcase.getExpectedV3Data();
            zpath = testcase.ArrPathReadV3;

            actData = zarrread(zpath, Start=[2, 2]);
            testcase.verifyEqual(actData, expData(2:end, 2:end), ...
                'Failed to verify v3 read with Start.');

            actData = zarrread(zpath, Count=[2, 3]);
            testcase.verifyEqual(actData, expData(1:2, 1:3), ...
                'Failed to verify v3 read with Count.');

            actData = zarrread(zpath, Stride=[2, 2]);
            testcase.verifyEqual(actData, expData(1:2:end, 1:2:end), ...
                'Failed to verify v3 read with Stride.');

            actData = zarrread(zpath, Start=[2, 2], Count=[2, 3], Stride=[1, 2]);
            testcase.verifyEqual(actData, expData(2:3, 2:2:6), ...
                'Failed to verify v3 read with Start, Count, and Stride.');
        end

        function verifyChunkBoundaryReadV3(testcase)
            % Verify reads that span multiple chunks in a Zarr v3 array.
            expData = testcase.getExpectedV3Data();
            actData = zarrread(testcase.ArrPathReadV3, Start=[2, 3], Count=[3, 3]);
            testcase.verifyEqual(actData, expData(2:4, 3:5), ...
                'Failed to verify v3 read across chunk boundaries.');
        end

        function verifyFillValueReadV3(testcase)
            % Verify fill values are materialized for missing v3 chunks.
            expData = testcase.getExpectedV3FillData();
            actData = zarrread(testcase.ArrPathReadV3Fill);
            testcase.verifyEqual(actData, expData, ...
                'Failed to verify fill-value materialization for v3 reads.');

            actData = zarrread(testcase.ArrPathReadV3Fill, Start=[2, 2], Count=[4, 4]);
            testcase.verifyEqual(actData, expData(2:5, 2:5), ...
                'Failed to verify fill-value materialization for partial v3 reads.');
        end

        function verifyDimensionNamesFixtureV3(testcase)
            % Verify the runtime v3 read fixture keeps dimension names.
            info = zarrinfo(testcase.ArrPathReadV3);
            testcase.verifyEqual(string(info.dimension_names(:)), ["rows"; "cols"], ...
                'Failed to verify dimension names in the v3 read fixture.');
        end

        function verifyGroupInpError(testcase)
            % Verify error if a user tries to pass the group as input to
            % zarrread function.
            errID = 'MATLAB:Zarr:invalidZarrObject';
            testcase.verifyError(@()zarrread(testcase.GrpPathRead),errID);
        end

        function nonExistentArray(testcase)
            % Verify zarrread error when a user tries to read a non-existent
            % file.
            errID = 'MATLAB:Zarr:invalidZarrObject';
            testcase.verifyError(@()zarrread('nonexistent/'),errID);
        end

        function tooBigArray(testcase)
            % Verify zarrread error when a user tries to read data that is
            % too large

            bigDataPath = string(tempname) + "_myzarr";
            testcase.addTeardown(@()rmdir(bigDataPath, 's'));
            zarrcreate(bigDataPath, [100000,100000], Datatype='single');
            errID = 'MATLAB:Zarr:OutOfMemory';
            testcase.verifyError(@()zarrread(bigDataPath),errID);
        end

        function invalidFilePath(testcase)
            % Verify zarrread error when an invalid file path is used.

            % Using a cell input with a valid array path
            errID = 'MATLAB:validators:mustBeTextScalar';
            testcase.verifyError(@()zarrread({testcase.ArrPathRead}),errID);

            % Empty cell or double
            testcase.verifyError(@()zarrread({}),errID);
            testcase.verifyError(@()zarrread([]),errID);

            % Non-scalar input
            testcase.verifyError(@()zarrread([testcase.ArrPathRead,testcase.ArrPathRead]), ...
                errID);

            % Empty char
            errID = 'MATLAB:validators:mustBeNonzeroLengthText';
            testcase.verifyError(@()zarrread(''),errID);

            % Non-existent bucket
            inpPath = 's3://invalid/bucket/path';
            errID = 'MATLAB:Zarr:invalidZarrObject';
            testcase.verifyError(@()zarrread(inpPath),errID);
        end

        function invalidPartialReadParams(testcase)
            % Verify zarrread errors when invalid partial read
            % Start/Stride/Count are used.
            zpath = testcase.ArrPathReadSmall; % a 2D array, 3x4

            % Wrong number of dimensions in comparison to the array
            errID = 'MATLAB:Zarr:badPartialReadDimensions';
            wrongDims = [1,1,1];
            testcase.verifyError(@()zarrread(zpath,Start=wrongDims),errID);
            testcase.verifyError(@()zarrread(zpath,Stride=wrongDims),errID);
            testcase.verifyError(@()zarrread(zpath,Count=wrongDims),errID);

            % Invalid type
            errID = 'MATLAB:validators:mustBeNumeric';
            testcase.verifyError(@()zarrread(zpath,"Start",""),errID);
            testcase.verifyError(@()zarrread(zpath,"Stride",""),errID);
            testcase.verifyError(@()zarrread(zpath,"Count",""),errID);

            % Negative values
            inpVal = [-1 1];
            errID = 'MATLAB:validators:mustBePositive';
            testcase.verifyError(@()zarrread(zpath,"Start",inpVal),errID);
            testcase.verifyError(@()zarrread(zpath,"Stride",inpVal),errID);
            testcase.verifyError(@()zarrread(zpath,"Count",inpVal),errID);

            % Parameters out of bounds
            inpVal = [100 200];
            errID = 'MATLAB:Zarr:PartialReadOutOfBounds';
            testcase.verifyError(@()zarrread(zpath,"Start",inpVal),errID);
            testcase.verifyError(@()zarrread(zpath,"Stride",inpVal),errID);
            testcase.verifyError(@()zarrread(zpath,"Count",inpVal),errID);

            % Combination of parameters out of bounds
            testcase.verifyError(...
                @()zarrread(zpath,Start=[3 4],Count=[2 2]),errID)
        end
    end

    methods(Access = private)
        function createV3ReadFixtures(testcase)
            % Create Zarr v3 read fixtures using TensorStore directly.
            Zarr.pySetup;
            data = testcase.getExpectedV3Data();
            fillValue = single(-7);

            testcase.createDenseV3Array( ...
                testcase.ArrPathReadV3, ...
                data, ...
                [2 3], ...
                single(-9), ...
                ["rows", "cols"]);

            testcase.createSparseV3Array( ...
                testcase.ArrPathReadV3Fill, ...
                [6 6], ...
                [3 3], ...
                fillValue);
        end

        function createDenseV3Array(~, path, data, chunkShape, fillValue, dimensionNames)
            kvstore = Zarr.ZarrPy.createKVStore(false, Zarr.getFullPath(path));
            metadataJSON = tZarrRead.createV3MetadataJSON( ...
                size(data), "float32", chunkShape, fillValue, dimensionNames);

            Zarr.ZarrPy.createZarr3(kvstore, metadataJSON);
            Zarr.ZarrPy.writeZarr(kvstore, data, "zarr3", metadataJSON);
        end

        function createSparseV3Array(~, path, dataShape, chunkShape, fillValue)
            kvstore = Zarr.ZarrPy.createKVStore(false, Zarr.getFullPath(path));
            metadataJSON = tZarrRead.createV3MetadataJSON( ...
                dataShape, "float32", chunkShape, fillValue, []);

            topLeftChunk = single(reshape(1:9, 3, 3));
            bottomRightChunk = single(reshape(10:18, 3, 3));

            Zarr.ZarrPy.createZarr3(kvstore, metadataJSON);
            Zarr.ZarrPy.writeZarrRegion(kvstore, topLeftChunk, [0 0], [3 3], "zarr3", metadataJSON);
            Zarr.ZarrPy.writeZarrRegion(kvstore, bottomRightChunk, [3 3], [6 6], "zarr3", metadataJSON);
        end

        function data = getExpectedV3Data(~)
            data = single(reshape(1:24, 4, 6));
        end

        function data = getExpectedV3FillData(~)
            data = single(-7 * ones(6, 6));
            data(1:3, 1:3) = single(reshape(1:9, 3, 3));
            data(4:6, 4:6) = single(reshape(10:18, 3, 3));
        end
    end

    methods(Static, Access = private)
        function metadataJSON = createV3MetadataJSON(dataShape, dataType, chunkShape, fillValue, dimensionNames)
            codecs = [ ...
                struct("name", "bytes", "configuration", struct("endian", "little")), ...
                struct("name", "gzip", "configuration", struct("level", 1))];

            metadata = struct( ...
                "zarr_format", 3, ...
                "node_type", "array", ...
                "shape", reshape(double(dataShape), 1, []), ...
                "data_type", char(dataType), ...
                "chunk_grid", struct( ...
                    "name", "regular", ...
                    "configuration", struct("chunk_shape", reshape(double(chunkShape), 1, []))), ...
                "chunk_key_encoding", struct( ...
                    "name", "default", ...
                    "configuration", struct("separator", "/")), ...
                "fill_value", double(fillValue), ...
                "codecs", codecs);

            if ~isempty(dimensionNames)
                metadata.dimension_names = cellstr(reshape(string(dimensionNames), 1, []));
            end

            metadataJSON = jsonencode(metadata);
        end
    end
end
