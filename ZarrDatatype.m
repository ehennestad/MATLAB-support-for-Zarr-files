classdef ZarrDatatype
    %ZARRDATATYPE Datatype of Zarr data
    %   Represents the datatype mapping between MATLAB, Tensorstore, and Zarr

    % Copyright 2025 The MathWorks, Inc.
    
    properties(Constant, Hidden)
        % Same-length arrays that represent mapping between 
        % three kinds of datatypes
        MATLABTypes = ["logical", "uint8", "int8", "uint16", "int16",...
            "uint32", "int32", "uint64", "int64", "single", "double"];
        TensorstoreTypes = ["bool", "uint8", "int8", "uint16", "int16",...
            "uint32", "int32", "uint64", "int64", "float32", "float64"];
        ZarrTypes   = ["|b1", "|u1", "|i1", "<u2", "<i2",...
            "<u4", "<i4", "<u8", "<i8", "<f4", "<f8"];
        ZarrV3Types = ["bool", "uint8", "int8", "uint16", "int16",...
            "uint32", "int32", "uint64", "int64", "float32", "float64"];
    end
    
    properties (SetAccess = immutable, GetAccess=private, Hidden)
        % Index into datatype arrays (for simple types)
        Index (1,1) int32
    end

    properties (SetAccess = immutable, GetAccess=public, Hidden)
        % Compound datatype metadata.
        IsCompound (1,1) logical = false
        CompoundFields = {}
    end

    properties (Dependent, SetAccess = immutable)
        % Dependent properties representing the corresponding datatype in
        % Zarr, Tensorstore, and MATLAB
        ZarrType
        ZarrV3Type
        TensorstoreType
        MATLABType
    end

    methods (Hidden)
        % "Private" constructor - should not be used directly. 
        % Use from*Type() static methods instead.
        function obj = ZarrDatatype(ind, isCompound, compoundFields)
            arguments
                ind (1,1) int32 = 0
                isCompound (1,1) logical = false
                compoundFields = {}
            end

            obj.Index = ind;
            obj.IsCompound = isCompound;
            obj.CompoundFields = compoundFields;
        end
    end

    methods
        function zType = get.ZarrType(obj)
            % Get the corresponding Zarr datatype
            if obj.IsCompound
                zType = obj.CompoundFields;
            else
                zType = ZarrDatatype.ZarrTypes(obj.Index);
            end
        end

        function tType = get.TensorstoreType(obj)
            % Get the corresponding Tensorstore datatype
            if obj.IsCompound
                tType = "struct";
            else
                tType = ZarrDatatype.TensorstoreTypes(obj.Index);
            end
        end

        function zType = get.ZarrV3Type(obj)
            % Get the corresponding Zarr v3 datatype
            if obj.IsCompound
                zType = obj.CompoundFields;
            else
                zType = ZarrDatatype.ZarrV3Types(obj.Index);
            end
        end

        function mType = get.MATLABType(obj)
            % Get the corresponding MATLAB datatype
            if obj.IsCompound
                mType = "struct";
            else
                mType = ZarrDatatype.MATLABTypes(obj.Index);
            end
        end
    end

    methods (Static)
        function obj = fromMATLABType(MATLABType)
            % Create a datatype object based on MATLAB datatype name
            arguments
                MATLABType (1,1) string {ZarrDatatype.mustBeMATLABType}
            end

            ind = find(MATLABType == ZarrDatatype.MATLABTypes);
            obj = ZarrDatatype(ind);
        end

        function obj = fromTensorstoreType(tensorstoreType)
            % Create a datatype object based on Tensorstore datatype name
            arguments
                tensorstoreType (1,1) string {ZarrDatatype.mustBeTensorstoreType}
            end

            ind = find(tensorstoreType == ZarrDatatype.TensorstoreTypes);
            obj = ZarrDatatype(ind);
        end

        function obj = fromZarrType(zarrType)
            % Create a datatype object based on Zarr v2 metadata datatype.
            if iscell(zarrType)
                obj = ZarrDatatype.fromCompoundFieldSpecs(zarrType, 2);
                return
            end

            zarrType = string(zarrType);
            ZarrDatatype.mustBeZarrType(zarrType);
            ind = find(zarrType == ZarrDatatype.ZarrTypes);
            obj = ZarrDatatype(ind);
        end

        function obj = fromV3Type(zarrType)
            % Create a datatype object based on Zarr v3 metadata datatype.
            if isstruct(zarrType)
                obj = ZarrDatatype.fromStructuredV3Type(zarrType);
                return
            end

            zarrType = string(zarrType);
            ind = find(zarrType == ZarrDatatype.ZarrV3Types);
            if isempty(ind)
                error("MATLAB:ZarrDatatype:unsupportedV3Type", ...
                    "Unsupported Zarr v3 datatype ""%s"".", zarrType)
            end
            obj = ZarrDatatype(ind);
        end

        function obj = fromMetadataType(type, zarrFormat)
            % Create a datatype object based on metadata datatype and version
            arguments
                type
                zarrFormat (1,1) double {mustBeMember(zarrFormat, [2, 3])}
            end

            if zarrFormat == 2
                obj = ZarrDatatype.fromZarrType(type);
            else
                obj = ZarrDatatype.fromV3Type(type);
            end
        end

        function mustBeMATLABType(type)
            % Validator for MATLAB types
            mustBeMember(type, ZarrDatatype.MATLABTypes);
        end

        function mustBeTensorstoreType(type)
            % Validator for Tensorstore types
            mustBeMember(type, ZarrDatatype.TensorstoreTypes)
        end

        function mustBeZarrType(type)
            % Validator for Zarr v2 scalar types
            mustBeMember(type, ZarrDatatype.ZarrTypes)
        end
    end

    methods (Static, Access = private)
        function obj = fromStructuredV3Type(zarrType)
            % Create a datatype object from a structured Zarr v3 data_type.
            if ~isfield(zarrType, 'name') || string(zarrType.name) ~= "structured"
                error("MATLAB:ZarrDatatype:unsupportedV3Type", ...
                    "Unsupported Zarr v3 datatype extension.");
            end

            if ~isfield(zarrType, 'configuration') || ...
                    ~isstruct(zarrType.configuration) || ...
                    ~isfield(zarrType.configuration, 'fields')
                error("MATLAB:ZarrDatatype:invalidCompoundType", ...
                    "Structured Zarr v3 datatypes must define configuration.fields.");
            end

            obj = ZarrDatatype.fromCompoundFieldSpecs(zarrType.configuration.fields, 3);
        end

        function obj = fromCompoundFieldSpecs(fieldSpecs, zarrFormat)
            if ~iscell(fieldSpecs)
                error("MATLAB:ZarrDatatype:invalidCompoundType", ...
                    "Compound datatype metadata must be a cell array of field definitions.");
            end

            compoundFields = cell(1, numel(fieldSpecs));
            for idx = 1:numel(fieldSpecs)
                [fieldName, fieldType, subarrayShape] = ...
                    ZarrDatatype.parseCompoundFieldSpec(fieldSpecs{idx});

                matlabType = ZarrDatatype.compoundFieldTypeToMATLABType(fieldType, zarrFormat);
                compoundFields{idx} = struct( ...
                    'name', fieldName, ...
                    'storageType', fieldType, ...
                    'matlabType', matlabType, ...
                    'subarrayShape', subarrayShape);
            end

            obj = ZarrDatatype(0, true, compoundFields);
        end

        function [fieldName, fieldType, subarrayShape] = parseCompoundFieldSpec(fieldSpec)
            if ~(iscell(fieldSpec) && ismember(numel(fieldSpec), [2, 3]))
                error("MATLAB:ZarrDatatype:invalidCompoundField", ...
                    "Each compound field must be a 2- or 3-element cell array.");
            end

            fieldName = string(fieldSpec{1});
            if strlength(fieldName) == 0
                error("MATLAB:ZarrDatatype:invalidCompoundField", ...
                    "Compound field names must be non-empty text values.");
            end

            fieldType = fieldSpec{2};
            if numel(fieldSpec) == 3
                subarrayShape = ZarrDatatype.normalizeSubarrayShape(fieldSpec{3});
            else
                subarrayShape = [];
            end
        end

        function subarrayShape = normalizeSubarrayShape(rawShape)
            if isempty(rawShape)
                subarrayShape = [];
                return
            end

            if iscell(rawShape)
                try
                    subarrayShape = cellfun(@double, rawShape);
                catch
                    error("MATLAB:ZarrDatatype:invalidCompoundField", ...
                        "Compound subarray shapes must be numeric.");
                end
            else
                subarrayShape = double(rawShape);
            end

            subarrayShape = reshape(subarrayShape, 1, []);
            if any(~isfinite(subarrayShape)) || any(subarrayShape < 1) || ...
                    any(subarrayShape ~= fix(subarrayShape))
                error("MATLAB:ZarrDatatype:invalidCompoundField", ...
                    "Compound subarray shapes must contain positive integers.");
            end
        end

        function matlabType = compoundFieldTypeToMATLABType(fieldType, zarrFormat)
            if isstruct(fieldType) || iscell(fieldType)
                error("MATLAB:ZarrDatatype:unsupportedCompoundFieldType", ...
                    "Nested or non-scalar compound field types are not supported.");
            end

            fieldType = string(fieldType);
            if zarrFormat == 2
                matlabType = ZarrDatatype.zarrV2FieldTypeToMATLABType(fieldType);
                return
            end

            matlabType = ZarrDatatype.zarrV3FieldTypeToMATLABType(fieldType);
        end

        function matlabType = zarrV2FieldTypeToMATLABType(fieldType)
            if any(fieldType == ZarrDatatype.ZarrTypes)
                idx = find(fieldType == ZarrDatatype.ZarrTypes, 1);
                matlabType = ZarrDatatype.MATLABTypes(idx);
                return
            end

            if any(startsWith(fieldType, ["<U", ">U", "|U", "<S", ">S", "|S"]))
                matlabType = "string";
                return
            end

            error("MATLAB:ZarrDatatype:unsupportedCompoundFieldType", ...
                "Unsupported Zarr v2 compound field type ""%s"".", fieldType);
        end

        function matlabType = zarrV3FieldTypeToMATLABType(fieldType)
            idx = find(fieldType == ZarrDatatype.ZarrV3Types, 1);
            if isempty(idx)
                error("MATLAB:ZarrDatatype:unsupportedCompoundFieldType", ...
                    "Unsupported Zarr v3 compound field type ""%s"".", fieldType);
            end

            matlabType = ZarrDatatype.MATLABTypes(idx);
        end
    end
end
