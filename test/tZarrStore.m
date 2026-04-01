classdef tZarrStore < matlab.unittest.TestCase
    % Tests for store abstractions used by metadata-only operations.

    methods(TestClassSetup)
        function addSrcCodePath(testcase)
            import matlab.unittest.fixtures.PathFixture
            testcase.applyFixture(PathFixture(fullfile('..'),'IncludeSubfolders',true))
        end
    end

    methods(Test)
        function fileSystemStoreHandlesMetadataOperations(testcase)
            import matlab.unittest.fixtures.WorkingFolderFixture
            testcase.applyFixture(WorkingFolderFixture);

            store = getZarrStore("root");
            store.makeDir("");
            store.makeDir("grp");
            store.writeText("grp/.zgroup", jsonencode(struct("zarr_format", "2")));
            store.writeBytes("grp/data.bin", uint8([1 2 3]));

            testcase.verifyClass(store, "FileSystemStore");
            testcase.verifyTrue(store.exists("grp"));
            testcase.verifyTrue(store.isDirectory("grp"));
            testcase.verifyEqual(store.resolve("grp/.zgroup"), fullfile("root", "grp", ".zgroup"));
            testcase.verifyEqual(store.readText("grp/.zgroup"), '{"zarr_format":"2"}');
            testcase.verifyEqual(store.readBytes("grp/data.bin"), uint8([1; 2; 3]));
            testcase.verifyEqual(sort(store.listChildren("grp")), [".zgroup", "data.bin"]);
        end

        function remotePrototypeResolvesChildLocations(testcase)
            store = getZarrStore("s3://bucket/example.zarr");

            testcase.verifyClass(store, "TensorStoreBackedStore");
            testcase.verifyEqual(store.resolve("child/zarr.json"), ...
                "s3://bucket/example.zarr/child/zarr.json");
        end

        function remotePrototypeReportsUnsupportedOperations(testcase)
            store = getZarrStore("s3://bucket/example.zarr");

            testcase.verifyError(@() store.exists("zarr.json"), ...
                "MATLAB:ZarrStore:unsupportedOperation");
            testcase.verifyError(@() zarrinfo("s3://bucket/example.zarr"), ...
                "MATLAB:ZarrStore:unsupportedOperation");
        end
    end
end
