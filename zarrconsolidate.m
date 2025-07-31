function zarrconsolidate(filepath)
%ZARRCONSOLIDATE Consolidate metadata for a Zarr file hierarchy
%   ZARRCONSOLIDATE(FILEPATH) consolidates metadata from all arrays and 
%   groups in a Zarr hierarchy rooted at FILEPATH into a single 
%   .zmetadata file. This can significantly improve performance when 
%   accessing metadata across a large hierarchy, especially over network 
%   filesystems.
%
%   The consolidated metadata is stored in a .zmetadata file at the root
%   of the hierarchy. This function recursively walks through the entire 
%   Zarr hierarchy, collecting metadata from all .zarray, .zgroup, and 
%   .zattrs files and creates a consolidated view. After consolidation, 
%   reading metadata from any child node will only require reading the 
%   root .zmetadata file.
%
%   Note: This function only supports Zarr v2 format hierarchies.
%
%   Example:
%       % Consolidate metadata for a Zarr file
%       zarrconsolidate('mydata.zarr')

    arguments
        filepath {mustBeTextScalar, mustBeNonzeroLengthText, mustBeZarrV2}
    end
    
    % Deeply nested zarr files might end up creating very long names.
    %warnState = warning('off', 'MATLAB:namelengthmaxexceeded');
    %cleanupObj = onCleanup(@() warning(warnState) );

    % Initialize map which is to collect valid field names and corresponding 
    % zarr keys when consolidating metadata. This map is then used to
    % ensure the final output has proper zarr keys for each of the zarr
    % elements
    validNameToZarrKeyMap = containers.Map;
    
    % Collect metadata from the entire hierarchy
    consolidatedMetadata = collectHierarchyMetadata(filepath, '', validNameToZarrKeyMap);
    
    % Write consolidated metadata for Zarr file
    writeConsolidatedMetadata(filepath, consolidatedMetadata, validNameToZarrKeyMap);
end

function metadata = collectHierarchyMetadata(rootPath, relativePath, validNameToZarrKeyMap)
%COLLECTHIERARCHYMETADATA Recursively collect metadata from Zarr hierarchy
%   Walks through the directory structure and collects metadata from all
%   .zarray, .zgroup, and .zattrs files, storing them as separate entries

    metadata = struct();
    
    % Build current path
    if isempty(relativePath)
        currentPath = rootPath;
        keyPrefix = '';
    else
        currentPath = fullfile(rootPath, relativePath);
        keyPrefix = [relativePath '/'];
    end

    % Add root metadata
    if isempty(relativePath)
        % Add root group metadata (.zgroup)
        if isfile(fullfile(currentPath, '.zgroup'))
            rootGroupMeta = collectGroupCoreMetadata(currentPath);
            metadata.('x_zgroup') = rootGroupMeta;
            validNameToZarrKeyMap('x_zgroup') = '.zgroup';
        end
        
        % Add root attributes (.zattrs) if they exist
        if isfile(fullfile(currentPath, '.zattrs'))
            rootAttrs = readZattrs(currentPath);
            if ~isempty(rootAttrs)
                metadata.('x_zattrs') = rootAttrs;
                validNameToZarrKeyMap('x_zattrs') = '.zattrs';
            end
        end
    end
    
    % Get directory listing
    try
        dirContents = dir(currentPath);
        dirContents = dirContents(~ismember({dirContents.name}, {'.', '..'}));
    catch
        return;
    end
    
    % Process each item in directory
    for i = 1:length(dirContents)
        item = dirContents(i);
        itemPath = fullfile(currentPath, item.name);
        
        if item.isdir
            % Check if this directory is a Zarr array or group
            if isfile(fullfile(itemPath, '.zarray'))
                % This is a Zarr array - collect separate .zarray and .zattrs
                arrayKey = [keyPrefix item.name];
                
                % Collect .zarray metadata
                arrayMeta = collectArrayCoreMetadata(itemPath);
                zarrayKey = [arrayKey '/.zarray'];
                validKey = makeValidFieldName(zarrayKey, validNameToZarrKeyMap);
                metadata.(validKey) = arrayMeta;
                
                % Collect .zattrs metadata if it exists
                if isfile(fullfile(itemPath, '.zattrs'))
                    metadata = addAttributeMetadata(...
                        metadata, itemPath, arrayKey, validNameToZarrKeyMap);
                end
                
            elseif isfile(fullfile(itemPath, '.zgroup'))
                % This is a Zarr v2 group - collect separate .zgroup and .zattrs
                groupKey = [keyPrefix item.name];
                
                % Collect .zgroup metadata
                groupMeta = collectGroupCoreMetadata(itemPath);
                zgroupKey = [groupKey '/.zgroup'];
                validKey = makeValidFieldName(zgroupKey, validNameToZarrKeyMap);
                metadata.(validKey) = groupMeta;
                
                % Collect .zattrs metadata if it exists
                if isfile(fullfile(itemPath, '.zattrs'))
                    metadata = addAttributeMetadata(...
                        metadata, itemPath, groupKey, validNameToZarrKeyMap);
                end
                
                % Recursively collect metadata from this group
                subPath = fullfile(relativePath, item.name);
                subMetadata = collectHierarchyMetadata(rootPath, subPath, validNameToZarrKeyMap);
                metadata = mergeMetadata(metadata, subMetadata);
            end
        end
    end
end

function arrayMeta = collectArrayCoreMetadata(arrayPath)
%COLLECTARRAYCORE METADATA Collect core metadata for a Zarr array (.zarray only)
    
    % Read .zarray file
    if isfile(fullfile(arrayPath, '.zarray'))
        zarrStr = fileread(fullfile(arrayPath, '.zarray'));
        arrayMeta = jsondecode(zarrStr);
    else
        error("MATLAB:zarrconsolidate:missingZarray",...
            "Missing .zarray file in array directory: %s", arrayPath);
    end
end

function groupMeta = collectGroupCoreMetadata(groupPath)
%COLLECTGROUPCOREMETADATA Collect core metadata for a Zarr group (.zgroup only)
    
    % Read .zgroup file
    if isfile(fullfile(groupPath, '.zgroup'))
        zgroupStr = fileread(fullfile(groupPath, '.zgroup'));
        groupMeta = jsondecode(zgroupStr);
    else
        error("MATLAB:zarrconsolidate:missingZgroup",...
            "Missing .zgroup file in group directory: %s", groupPath);
    end
end

function metadata = addAttributeMetadata(metadata, itemPath, itemKey, validNameToZarrKeyMap)
    % Collect .zattrs metadata if it exists
    if isfile(fullfile(itemPath, '.zattrs'))
        attrMeta = readZattrs(itemPath);
        if ~isempty(attrMeta)
            zattrsKey = [itemKey '/.zattrs'];
            validKey = makeValidFieldName(zattrsKey, validNameToZarrKeyMap);
            metadata.(validKey) = attrMeta;
        end
    end
end

function merged = mergeMetadata(meta1, meta2)
%MERGEMETADATA Merge two metadata structures
    merged = meta1;
    fields = fieldnames(meta2);
    for i = 1:length(fields)
        merged.(fields{i}) = meta2.(fields{i});
    end
end

function validName = makeValidFieldName(name, validNameMap)
%MAKEVALIDFIELDNAME Convert path to valid MATLAB field name
    % Replace path separators and invalid characters with underscores
    validName = strrep(name, '/', '_');
    validName = strrep(validName, '\', '_');
    validName = strrep(validName, '.', '_');
    validName = strrep(validName, '-', '_');
    
    % Ensure it starts with a letter
    if ~isempty(validName) && ~isletter(validName(1))
        validName = ['x' validName];
    end
    
    % Ensure it's not empty
    if isempty(validName)
        validName = 'root';
    end

    if numel(validName) > 63
        validName = validName(end-62:end);
        if startsWith(validName, '_')
            validName = extractAfter(validName, '_');
        end
    end

    % NB: Side effect; handle object is updated:
    validNameMap(validName) = name; %#ok<NASGU>
end

function writeConsolidatedMetadata(filepath, metadata, validNameToKeyMap)
%WRITECONSOLIDATEDMETADATA Write consolidated metadata for Zarr file
    
    % Create .zmetadata structure
    zmetadata = struct();
    zmetadata.zarr_consolidated_format = 1;
    zmetadata.metadata = struct();

    % Add root group metadata (.zgroup)
    if isfile(fullfile(filepath, '.zgroup'))
        rootGroupMeta = collectGroupCoreMetadata(filepath);
        zmetadata.metadata.('x_zgroup') = rootGroupMeta;
        validNameToKeyMap('x_zgroup') = '.zgroup';
    end
    
    % Add root attributes (.zattrs) if they exist
    if isfile(fullfile(filepath, '.zattrs'))
        rootAttrs = readZattrs(filepath);
        if ~isempty(rootAttrs)
            zmetadata.metadata.('x_zattrs') = rootAttrs;
            validNameToKeyMap('x_zattrs') = '.zattrs';
        end
    end

    % Add all collected metadata using MATLAB valid field names first
    metaFields = fieldnames(metadata);
    for i = 1:length(metaFields)
        validFieldName = metaFields{i};
        zmetadata.metadata.(validFieldName) = metadata.(validFieldName);
    end
    
    % Convert to JSON string with valid MATLAB names
    jsonStr = jsonencode(zmetadata, 'PrettyPrint', true);
    
    % Use regexp to replace the valid MATLAB field names with Zarr keys
    validNames = keys(validNameToKeyMap);
    for i = 1:length(validNames)
        validFieldName = validNames{i};
        zarrKey = validNameToKeyMap(validFieldName);
        
        % Create the pattern to match the JSON field name
        % This will match "validFieldName": in the JSON
        pattern = ['"' validFieldName '"\s*:'];
        replacement = ['"' zarrKey '":'];
        jsonStr = regexprep(jsonStr, pattern, replacement);
    end
    
    % Write .zmetadata file
    zmetadataFile = fullfile(filepath, '.zmetadata');
    
    fid = fopen(zmetadataFile, 'w');
    if fid == -1
        error("MATLAB:zarrconsolidate:fileWriteFailure",...
            "Could not create .zmetadata file: %s", zmetadataFile);
    end
    fwrite(fid, jsonStr, 'char');
    fclose(fid);
end

function mustBeZarrV2(filepath)
    % Validate that the filepath points to a valid Zarr v2 group
    if ~isfile(fullfile(filepath, '.zgroup'))
        error("MATLAB:zarrconsolidate:invalidZarr",...
            "Invalid file path. Path must refer to a valid Zarr v2 group (containing .zgroup file).");
    end

    % Check if this is indeed Zarr v2
    rootGroupInfo = zarrinfo(filepath);
    if ~isfield(rootGroupInfo, 'zarr_format') || rootGroupInfo.zarr_format ~= 2
        error("MATLAB:zarrconsolidate:unsupportedFormat",...
            "Only Zarr v2 format is supported. Found zarr_format: %s", ...
            string(rootGroupInfo.zarr_format));
    end
end
