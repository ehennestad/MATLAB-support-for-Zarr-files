classdef tZarrGroupCreate < matlab.unittest.TestCase
    % Tests for zarrgroupcreate function.

    methods(TestClassSetup)
        function addSrcCodePath(testcase)
            import matlab.unittest.fixtures.PathFixture
            testcase.applyFixture(PathFixture(fullfile('..'),'IncludeSubfolders',true))
        end
    end

    methods(Test)
        function createFreshV3Group(testcase)
            import matlab.unittest.fixtures.WorkingFolderFixture
            testcase.applyFixture(WorkingFolderFixture);

            zarrgroupcreate('grp');
            info = zarrinfo('grp');
            testcase.verifyEqual(info.node_type, 'group');
            testcase.verifyEqual(info.zarr_format, 3);
        end

        function createNestedGroups(testcase)
            import matlab.unittest.fixtures.WorkingFolderFixture
            testcase.applyFixture(WorkingFolderFixture);

            zarrgroupcreate(fullfile('root', 'a', 'b'), ZarrFormat=3);
            testcase.verifyEqual(zarrversion('root'), 3);
            testcase.verifyEqual(zarrversion(fullfile('root', 'a')), 3);
            testcase.verifyEqual(zarrversion(fullfile('root', 'a', 'b')), 3);
        end

        function alreadyExistingGroupIsStable(testcase)
            import matlab.unittest.fixtures.WorkingFolderFixture
            testcase.applyFixture(WorkingFolderFixture);

            zarrgroupcreate('grp', ZarrFormat=2);
            zarrgroupcreate('grp', ZarrFormat=2);
            testcase.verifyTrue(isfile(fullfile('grp', '.zgroup')));
        end

        function invalidParentPath(testcase)
            import matlab.unittest.fixtures.WorkingFolderFixture
            testcase.applyFixture(WorkingFolderFixture);

            zarrcreate('arr', [5 5]);
            testcase.verifyError(@() zarrgroupcreate(fullfile('arr', 'child')), ...
                'MATLAB:zarrgroupcreate:invalidParentPath');
        end
    end
end
