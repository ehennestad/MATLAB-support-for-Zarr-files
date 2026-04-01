classdef tZarrCreate < SharedZarrTestSetup
    % Tests for zarrcreate function to create Zarr files in MATLAB.

    % Copyright 2025 The MathWorks, Inc.

    methods(Test)
        function createDefaultArray(testcase)
            % Verify that zarrcreate correctly creates a Zarr array with
            % all default properties

            zarrcreate(testcase.ArrPathWrite,testcase.ArrSize);
            
            expInfo.chunks = testcase.ArrSize';
            expInfo.compressor = [];
            expInfo.dimension_separator = '.';
            expInfo.dtype = '<f8';
            expInfo.fill_value = [];
            expInfo.filters = [];
            expInfo.order = 'C';
            expInfo.shape = testcase.ArrSize';
            expInfo.zarr_format = 2;
            expInfo.node_type = 'array';

            actInfo = zarrinfo(testcase.ArrPathWrite);
            testcase.verifyEqual(actInfo, expInfo,...
                'Failed to verify creating Zarr array with default properties');
        end

        function createIntermediateZgroups(testcase)
            % Verify that zarrcreate creates zarr groups when given a
            % nested path
            arrayPath = fullfile(testcase.GrpPathWrite, "v3", "A", "B", "arr");
            zarrcreate(arrayPath, testcase.ArrSize);
            [groupPath, ~, ~] = fileparts(arrayPath);

            testcase.verifyTrue(isfile(fullfile(groupPath, ".zgroup")),...
                ".zgroup file was not created")

            grpInfo = zarrinfo(groupPath);
            expFormat = '2';
            expType = 'group';

            testcase.verifyEqual(grpInfo.zarr_format, expFormat,...
                "Unexpected Zarr group format");
            testcase.verifyEqual(grpInfo.node_type, expType,...
                "Unexpected Zarr group node type");
        end

        function createArrayRelativePath(testcase)
            % Verify that the array is successfully created if a relative
            % path is used.
            newDir = 'myFolder';
            currDir = pwd;
            mkdir(newDir);
            testcase.addTeardown(@()cd(currDir));

            cd(newDir);
            inpPath = fullfile('..','myGrp','myArr');
            zarrcreate(inpPath,[10 10]);
            arrInfo = zarrinfo(inpPath);
            testcase.verifyEqual(arrInfo.zarr_format,2,'Failed to verify Zarr array format');
            testcase.verifyEqual(arrInfo.node_type,'array','Unexpected Zarr array node type');
        end

        function createDefaultArrayV3(testcase)
            % Verify that zarrcreate can build a Zarr v3 array with the
            % default portable codec profile.
            zarrcreate(testcase.ArrPathWrite, testcase.ArrSize, ZarrFormat=3);

            actInfo = zarrinfo(testcase.ArrPathWrite);
            testcase.verifyEqual(actInfo.zarr_format, 3);
            testcase.verifyEqual(actInfo.node_type, 'array');
            testcase.verifyEqual(actInfo.shape(:), testcase.ArrSize');
            testcase.verifyEqual(string(actInfo.data_type), "float64");
            testcase.verifyEqual(actInfo.chunk_shape(:), testcase.ArrSize');
            testcase.verifyEqual(string(actInfo.chunk_key_encoding.name), "default");
            testcase.verifyEqual(actInfo.fill_value, 0);
            testcase.verifyEqual({actInfo.codecs.name}, {'bytes', 'gzip'});
            testcase.verifyEqual(string(actInfo.codecs(1).configuration.endian), "little");
            testcase.verifyEqual(actInfo.codecs(2).configuration.level, 1);
        end

        function createIntermediateZgroupsV3(testcase)
            % Verify nested v3 array creation uses v3 group metadata for
            % intermediate directories.
            arrayPath = fullfile(testcase.GrpPathWrite, "A", "B", "arr");
            zarrcreate(arrayPath, testcase.ArrSize, ZarrFormat=3);
            [groupPath, ~, ~] = fileparts(arrayPath);

            testcase.verifyTrue(isfile(fullfile(groupPath, "zarr.json")), ...
                "zarr.json file was not created")
            testcase.verifyFalse(isfile(fullfile(groupPath, ".zgroup")), ...
                "Unexpected v2 .zgroup file was created for a v3 hierarchy")

            grpInfo = zarrinfo(groupPath);
            testcase.verifyEqual(grpInfo.zarr_format, 3, ...
                "Unexpected Zarr group format");
            testcase.verifyEqual(grpInfo.node_type, 'group', ...
                "Unexpected Zarr group node type");
        end

        function createArrayV3LegacyCompressionSyntax(testcase)
            % Verify v3 creation maps the legacy Compression syntax onto
            % the supported bytes + gzip codec chain.
            compression.id = 'gzip';
            compression.level = 5;

            zarrcreate(testcase.ArrPathWrite, testcase.ArrSize, ...
                Compression=compression, ZarrFormat=3);

            actInfo = zarrinfo(testcase.ArrPathWrite);
            testcase.verifyEqual({actInfo.codecs.name}, {'bytes', 'gzip'});
            testcase.verifyEqual(actInfo.codecs(2).configuration.level, 5);
        end

        function invalidFilePath(testcase)
            % Verify error when an invalid file path is used as an input to
            % zarrcreate function.

            % Empty
            errID = 'MATLAB:validators:mustBeNonempty';
            testcase.verifyError(@()zarrcreate('',testcase.ArrSize),errID);

            % Non-scalar
            errID = 'MATLAB:validators:mustBeTextScalar';
            testcase.verifyError(@()zarrcreate([testcase.ArrPathWrite,testcase.ArrPathWrite], ...
                testcase.ArrSize),errID);

            % Non-text input
            testcase.verifyError(@()zarrcreate([],testcase.ArrSize),errID);

            % Invalid bucket path format
            errID = 'MATLAB:Zarr:invalidS3URL';
            inpPath = 'https://invalid/arr/path';
            testcase.verifyError(@()zarrcreate(inpPath,[10 10]),errID);
            
            inpPath = 'http://invalid/arr/path';
            testcase.verifyError(@()zarrcreate(inpPath,[10 10]),errID);

            % Non-existent bucket path 
            errID = 'MATLAB:Zarr:invalidPath';
            inpPath = 's3://invalid/bucket/path';
            testcase.verifyError(@()zarrcreate(inpPath,[10 10]),errID);
        end

        function invalidFilePathWindows(testcase)
            % Verify error when a non-existent Windows path starting with
            % "\\" is used

            testcase.assumeTrue(ispc, "Windows-specific test")
            errID = 'MATLAB:Zarr:invalidPath';
            inpPath = '\\invalid\bucket\path';
            testcase.verifyError(@()zarrcreate(inpPath,[10 10]),errID);
        end

        function pathContainingInvalidChars(testcase)
            % Verify error when the array or group name contains
            % unsupported characters.
            testcase.assumeTrue(ispc,'Filtered on other platforms');
            testcase.verifyError(@()zarrcreate('grp*/arr',testcase.ArrSize),testcase.PyException);
            testcase.verifyError(@()zarrcreate('grp/arr*',testcase.ArrSize),testcase.PyException);
        end

        function chunkSizeGreaterThanArraySize(testcase)
            % Verify error when the chunk size is greater than the array
            % size.
            errID = 'MATLAB:zarrcreate:chunkSizeGreater';
            chunkSize = [30 35];
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'ChunkSize',chunkSize),errID);
        end

        function chunkSizeMismatch(testcase)
            % Verify error when there is a mismatch between Array size and
            % Chunk size.
            arrSize = [10 12 5];
            chunkSize = [4 5];
            errID = 'MATLAB:zarrcreate:chunkDimsMismatch';
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,arrSize, ...
                'ChunkSize',chunkSize),errID);
        end

        function invalidClevelBlosc(testcase)
            % Verify error when an invalid clevel value is used with blosc
            % compression. Valid values are [0 9], where 0 is for no compression.
            comp.id = 'blosc';
            level = {-1,10,NaN};
            comp.cname = 'blosclz';
            comp.shuffle = -1;

            for i = 1:length(level)
                comp.clevel = level{i};
                testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                    'Compression',comp),testcase.PyException);
            end
        end

        function invalidBlockSizeBlosc(testcase)
            % Verify error when an invalid blocksize value is used with blosc
            % compression. Valid values for blocksize are [0 inf].
            comp.id = 'blosc';
            comp.level = 5;
            comp.cname = 'blosclz';
            comp.shuffle = -1;
            blocksize = {-1,[2 2],NaN};

            for i = 1:length(blocksize)
                comp.blocksize = blocksize{i};
                testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                    'Compression',comp),testcase.PyException);
            end
        end

        function invalidCnameBlosc(testcase)
            % Verify error when an invalid cname value is used with blosc
            % compression.
            comp.id = 'blosc';
            comp.level = 5;
            cname = {'random','',0};
            comp.shuffle = -1;
            comp.blocksize = 5;

            for i = 1:length(cname)
                comp.cname = cname{i};
                testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                    'Compression',comp),testcase.PyException);
            end
        end

        function invalidShuffleBlosc(testcase)
            % Verify error when an invalid shuffle value is used with blosc
            % compression. The valid values are -1, 0, 1, and 2.
            comp.id = 'blosc';
            comp.level = 5;
            comp.cname = 'blosclz';
            shuffle = {-2,3,inf,NaN};
            comp.blocksize = 5;

            for i = 1:length(shuffle)
                comp.shuffle = shuffle{i};
                testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                    'Compression',comp),testcase.PyException);
            end
        end

        function invalidChunkSize(testcase)
            % Verify error when an invalid type for the chunk size is used.

            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'ChunkSize',5),'MATLAB:zarrcreate:chunkDimsMismatch');
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'ChunkSize',[]),'MATLAB:zarrcreate:chunkDimsMismatch');
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'ChunkSize',[0 0]),'MATLAB:validators:mustBePositive');
        end

        function invalidFillValue(testcase)
            % Verify error when an invalid type for the fill value is used.

            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                "FillValue",[-9 -9]),'MATLAB:zarrcreate:invalidFillValueType');
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                "FillValue","none"),'MATLAB:validators:mustBeNumericOrLogical');
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize,...
                Datatype="int8", FillValue=1.4), 'MATLAB:zarrcreate:invalidFillValueType')
        end

        function invalidZarrFormat(testcase)
            % Verify unsupported ZarrFormat values are rejected.
            testcase.verifyError(@() zarrcreate(testcase.ArrPathWrite, testcase.ArrSize, ...
                ZarrFormat=4), 'MATLAB:validators:mustBeMember');
        end

        function invalidV3CodecChain(testcase)
            % Verify unsupported v3 codec chains are rejected early.
            codecs = [ ...
                struct("name", "bytes", "configuration", struct("endian", "little")), ...
                struct("name", "zstd", "configuration", struct("level", 1))];

            testcase.verifyError(@() zarrcreate(testcase.ArrPathWrite, testcase.ArrSize, ...
                Compression=codecs, ZarrFormat=3), ...
                'MATLAB:Zarr:unsupportedV3CodecChain');
        end

        function specialFillValue(testcase)
            % Verify creating Zarr arrays using special fill values like
            % NaN and Inf

            expData = [NaN,NaN];
            zarrcreate(testcase.ArrPathWrite, [1,2], FillValue=NaN)
            actData = zarrread(testcase.ArrPathWrite);
            testcase.verifyEqual(expData, actData)

            expData = [Inf,Inf];
            zarrcreate(testcase.ArrPathWrite, [1,2], FillValue=Inf)
            actData = zarrread(testcase.ArrPathWrite);
            testcase.verifyEqual(expData, actData)
        end

        function invalidSizeInput(testcase)
            % Verify error when an invalid size input is used.

            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,[]), ...
                'MATLAB:validators:mustBeNonempty');
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,Inf), ...
                'MATLAB:validators:mustBeFinite');
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,-2), ...
                'MATLAB:validators:mustBePositive');
        end

        function invalidDatatype(testcase)
            % Verify the error when an unsupported datatype is used.
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,...
                testcase.ArrSize,Datatype="bla"),...
                'MATLAB:validators:mustBeMember');
        end

        function invalidCompressionInputType(testcase)
            % Verify error when an invalid compression value is used.
            %testcase.assumeTrue(false,'Filtered until the issue is fixed.');
            comp.id = 'random';
            errID = 'MATLAB:Zarr:invalidCompressionID';
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),errID);

            comp = 'zlib';
            errID = 'MATLAB:zarrcreate:invalidCompression';
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),errID);
        end

        function invalidCompressionMember(testcase)
            % Verify error when additional compression members (cname, blocksize,
            % and shuffle) are used. These members are not supported for
            % compression other than blosc.
            compType = {'gzip','zlib','bz2','zstd'};
            comp.level = 5;
            comp.cname = 'blosclz';
            comp.shuffle = -1;

            for i = 1:length(compType)
                comp.id = compType{i};
                testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                    'Compression',comp),testcase.PyException);
            end
        end

        function zlibInvalidCompressionLevel(testcase)
            % Verify error when an invalid compression level is used.
            % For zlib, valid values are [0 9]
            comp.level = 5;
            errID = 'MATLAB:Zarr:missingCompressionID';
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),errID);

            comp.id = 'zlib';
            comp.level = -1;
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),testcase.PyException);

            comp.level = 10;
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),testcase.PyException);

            comp.level = [];
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),testcase.PyException);
        end

        function gzipInvalidCompressionLevel(testcase)
            % Verify error when an invalid compression level is used.
            % For gzip, valid values are [0 9]
            comp.id = 'gzip';
            comp.level = -1;
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),testcase.PyException);

            comp.level = 10;
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),testcase.PyException);

            comp.level = [];
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),testcase.PyException);
        end

        function bz2InvalidCompressionLevel(testcase)
            % Verify error when an invalid compression level is used.
            % For zlib, valid values are [1 9]
            comp.id = 'bz2';
            comp.level = 0;
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),testcase.PyException);

            comp.level = 10;
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),testcase.PyException);

            comp.level = [];
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),testcase.PyException);
        end

        function zstdInvalidCompressionLevel(testcase)
            % Verify error when an invalid compression level is used.
            % For zlib, valid values are [1 9]
            comp.id = 'zstd';
            comp.level = -131073;
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),testcase.PyException);

            comp.level = 23;
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),testcase.PyException);

            comp.level = [];
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Compression',comp),testcase.PyException);
        end

        function tooFewInputs(testcase)
            % Verify error when too few inputs are passed to the zarrcreate
            % function.
            errID = 'MATLAB:minrhs';
            testcase.verifyError(@()zarrcreate(),errID);
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite),errID);
        end

        function invalidParameter(testcase)
            % Verify error when an invalid NV pair for zarrcreate is used.
            errID =  'MATLAB:TooManyInputs';
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Random'),errID);
            testcase.verifyError(@()zarrcreate(testcase.ArrPathWrite,testcase.ArrSize, ...
                'Random',-1),errID);
        end
    end
end
