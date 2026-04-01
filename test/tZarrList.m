classdef tZarrList < matlab.unittest.TestCase
    % Tests for zarrlist function.

    methods(TestClassSetup)
        function addSrcCodePath(testcase)
            import matlab.unittest.fixtures.PathFixture
            testcase.applyFixture(PathFixture(fullfile('..'),'IncludeSubfolders',true))
        end
    end

    methods(Test)
        function listMixedChildNodes(testcase)
            import matlab.unittest.fixtures.WorkingFolderFixture
            testcase.applyFixture(WorkingFolderFixture);

            zarrgroupcreate('root', ZarrFormat=3);
            zarrgroupcreate(fullfile('root', 'grp2'), ZarrFormat=3);
            zarrcreate(fullfile('root', 'arr2'), [4 6]);
            mkdir(fullfile('root', 'not_a_node'));

            listing = zarrlist('root');
            testcase.verifyEqual({listing.name}, {'arr2', 'grp2'});
            testcase.verifyEqual({listing.node_type}, {'array', 'group'});
            testcase.verifyEqual([listing.zarr_format], [2 3]);
        end

        function invalidGroupInput(testcase)
            import matlab.unittest.fixtures.WorkingFolderFixture
            testcase.applyFixture(WorkingFolderFixture);

            zarrcreate('arr', [4 6]);
            testcase.verifyError(@() zarrlist('arr'), 'MATLAB:zarrlist:invalidZarrGroup');
        end
    end
end
