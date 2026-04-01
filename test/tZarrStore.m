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

        function remoteStoreResolvesChildLocations(testcase)
            store = getZarrStore("s3://bucket/example.zarr");

            testcase.verifyClass(store, "TensorStoreBackedStore");
            testcase.verifyEqual(store.resolve("child/zarr.json"), ...
                "s3://bucket/example.zarr/child/zarr.json");
        end

        function remoteStoreHandlesMetadataOperationsWithFileKvStore(testcase)
            Zarr.pySetup();
            rootPath = string(tempname);
            mkdir(rootPath);
            testcase.addTeardown(@()rmdir(rootPath, 's'));
            schema = py.dict(pyargs("driver", "file", ...
                "path", char(fullfile(rootPath, "example.zarr"))));
            store = TensorStoreBackedStore("s3://bucket/example.zarr", schema);

            store.writeText(".zgroup", jsonencode(struct("zarr_format", "2")));
            store.writeText("grp/.zarray", jsonencode(struct("zarr_format", "2")));
            store.writeBytes("grp/data.bin", uint8([4 5 6]));

            testcase.verifyTrue(store.exists(".zgroup"));
            testcase.verifyTrue(store.isDirectory("grp"));
            testcase.verifyEqual(char(store.readText(".zgroup")), '{"zarr_format":"2"}');
            testcase.verifyEqual(store.readBytes("grp/data.bin"), uint8([4; 5; 6]));
            testcase.verifyEqual(store.listChildren(""), "grp");
        end

        function remoteStoreMissingKeyErrors(testcase)
            Zarr.pySetup();
            rootPath = string(tempname);
            mkdir(rootPath);
            testcase.addTeardown(@()rmdir(rootPath, 's'));
            schema = py.dict(pyargs("driver", "file", ...
                "path", char(fullfile(rootPath, "example.zarr"))));
            store = TensorStoreBackedStore("s3://bucket/example.zarr", schema);

            testcase.verifyFalse(store.exists(".zgroup"));
            testcase.verifyError(@() store.readText(".zgroup"), ...
                "MATLAB:ZarrStore:keyNotFound");
        end
    end
end
