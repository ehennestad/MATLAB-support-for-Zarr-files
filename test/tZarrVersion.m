classdef tZarrVersion < matlab.unittest.TestCase
    % Tests for zarrversion function.

    properties(Constant)
        GrpPathV2 = "dataFiles/grp_v2"
        ArrPathV2 = "dataFiles/grp_v2/arr_v2"
        GrpPathV3 = "dataFiles/grp_v3"
        ArrPathV3 = "dataFiles/grp_v3/arr_v3"
    end

    methods(TestClassSetup)
        function addSrcCodePath(testcase)
            import matlab.unittest.fixtures.PathFixture
            testcase.applyFixture(PathFixture(fullfile('..'),'IncludeSubfolders',true))
        end
    end

    methods(Test)
        function versionForV2Array(testcase)
            testcase.verifyEqual(zarrversion(testcase.ArrPathV2), 2)
        end

        function versionForV2Group(testcase)
            testcase.verifyEqual(zarrversion(testcase.GrpPathV2), 2)
        end

        function versionForV3Array(testcase)
            testcase.verifyEqual(zarrversion(testcase.ArrPathV3), 3)
        end

        function versionForV3Group(testcase)
            testcase.verifyEqual(zarrversion(testcase.GrpPathV3), 3)
        end

        function invalidPath(testcase)
            testcase.verifyError(@() zarrversion('does/not/exist'), ...
                'MATLAB:zarrinfo:invalidZarrObject');
        end
    end
end
