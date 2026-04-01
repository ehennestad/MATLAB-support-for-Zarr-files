classdef tZarrInfo < matlab.unittest.TestCase
    % Tests for zarrinfo function to get info of the Zarr file in MATLAB.

    % Copyright 2025 The MathWorks, Inc.

    properties(Constant)
        GrpPathV2 = "dataFiles/grp_v2"
        ArrPathV2 = "dataFiles/grp_v2/arr_v2"
        GrpPathV3 = "dataFiles/grp_v3"
        ArrPathV3 = "dataFiles/grp_v3/arr_v3"
        ExpInfo = load(fullfile(pwd,"dataFiles","expZarrArrInfo.mat"))
    end

    methods(TestClassSetup)
        function addSrcCodePath(testcase)
            % Add source code path before running the tests
            import matlab.unittest.fixtures.PathFixture
            testcase.applyFixture(PathFixture(fullfile('..'),'IncludeSubfolders',true))
        end
    end

    methods(Test)
        function verifyArrayInfoV2(testcase)
            % Verify array info created with Zarr v2 format.
            actInfo = zarrinfo(testcase.ArrPathV2);
            expInfo = testcase.ExpInfo.zarrV2ArrInfo;
            testcase.verifyEqual(actInfo,expInfo,'Failed to verify array info.');
        end

        function verifyGroupInfoV2(testcase)
            % Verify group info created with Zarr v2 format.
            actInfo = zarrinfo(testcase.GrpPathV2);
            expInfo = testcase.ExpInfo.zarrV2GrpInfo;
            testcase.verifyEqual(actInfo,expInfo,'Failed to verify group info.');
        end

        function getArrayInfoRelativePath(testcase)
            % Verify array info if the input is using relative path to the
            % array.
            inpPath = fullfile('..','test',testcase.ArrPathV2);
            actInfo = zarrinfo(inpPath);
            expInfo = testcase.ExpInfo.zarrV2ArrInfo;
            testcase.verifyEqual(actInfo, expInfo, ['Failed to verify array info ' ...
                'with relative path.']);
        end

        function verifyArrayInfoV3(testcase)
            % Verify array info created with Zarr v3 format.
            actInfo = zarrinfo(testcase.ArrPathV3);
            expInfo = testcase.ExpInfo.zarrV3ArrInfo;
            testcase.verifyEqual(actInfo.shape, expInfo.shape, 'Failed to verify array shape.');
            testcase.verifyEqual(actInfo.data_type, expInfo.data_type, 'Failed to verify data type.');
            testcase.verifyEqual(actInfo.chunk_grid, expInfo.chunk_grid, 'Failed to verify chunk grid.');
            testcase.verifyEqual(actInfo.chunk_key_encoding, expInfo.chunk_key_encoding, ...
                'Failed to verify chunk key encoding.');
            testcase.verifyEqual(actInfo.fill_value, expInfo.fill_value, 'Failed to verify fill value.');
            testcase.verifyEqual(actInfo.codecs, expInfo.codecs, 'Failed to verify codecs.');
            testcase.verifyEqual(actInfo.attributes, expInfo.attributes, 'Failed to verify attributes.');
            testcase.verifyEqual(actInfo.zarr_format, expInfo.zarr_format, 'Failed to verify zarr format.');
            testcase.verifyEqual(actInfo.node_type, expInfo.node_type, 'Failed to verify node type.');
            testcase.verifyEqual(actInfo.storage_transformers, expInfo.storage_transformers, ...
                'Failed to verify storage transformers.');
            testcase.verifyEqual(actInfo.chunk_shape, [2; 5], 'Failed to verify derived chunk shape.');
            testcase.verifyEmpty(actInfo.dimension_names, 'Expected missing dimension names to be empty.');
        end

        function verifyGroupInfoV3(testcase)
            % Verify group info created with Zarr v3 format.
            actInfo = zarrinfo(testcase.GrpPathV3);
            expInfo = testcase.ExpInfo.zarrV3GrpInfo;
            testcase.verifyEqual(actInfo.attributes, expInfo.attributes, 'Failed to verify attributes.');
            testcase.verifyEqual(actInfo.zarr_format, expInfo.zarr_format, 'Failed to verify zarr format.');
            testcase.verifyEqual(actInfo.consolidated_metadata, expInfo.consolidated_metadata, ...
                'Failed to verify consolidated metadata.');
            testcase.verifyEqual(actInfo.node_type, expInfo.node_type, 'Failed to verify node type.');
        end

        function missingZgroupFile(testcase)
            % Verify error when using zarrinfo function on a directory not
            % containing .zgroup file.
            import matlab.unittest.fixtures.WorkingFolderFixture;
            testcase.applyFixture(WorkingFolderFixture);

            mkdir('prt_grp_write/arr1');
            grpPath = 'prt_grp_write/';
            errID = 'MATLAB:zarrinfo:invalidZarrObject';
            testcase.verifyError(@()zarrinfo(grpPath),errID);
        end

        function nonExistentArr(testcase)
            % Verify zarrinfo error when a user tries to read a non-existent
            % array.
            errID = 'MATLAB:zarrinfo:invalidZarrObject';
            testcase.verifyError(@()zarrinfo('nonexistentArr/'),errID);
        end

        function invalidInput(testcase)
            % Verify error when using invalid input with zarrinfo function.
            import matlab.unittest.fixtures.WorkingFolderFixture;
            testcase.applyFixture(WorkingFolderFixture);

            errID = 'MATLAB:TooManyInputs';
            testcase.verifyError(@()zarrinfo('testFiles/arr1','arr1'),errID);

            errID = 'MATLAB:validators:mustBeTextScalar';
            zarrcreate('prt_grp/arr_1',[10 10]);
            testcase.verifyError(@()zarrinfo({'prt_grp/arr_1'}),errID);
        end
    end
end
