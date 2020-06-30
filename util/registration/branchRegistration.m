function [xyOffset, offsetList] = branchRegistration(source, sections, varargin)
    % BRANCHREGISTRATION
    %
    % Description:
    %   Align vitread slice with sclerad slice based on median offset of
    %   all annotations linked between the two sections.
    %
    % Syntax:
    %	XY = branchRegistration(SOURCE, SECTIONS, WRITETOLOG, VISUALIZE);
    %
    % Inputs:
    %   source      Volume name or abbreviation
    %   sections    Two adjacent sections to align
    % Optional key/value inputs:
    %   View            Plot output (default = true)
    %   Save            Write to XY_OFFSET file (default = false)
    %   ShiftVitread    Align sclerad to vitread slice (default = false)
    %
    % Example:
    %   branchRegistration('i', [1121 1122]);
    %   branchRegistration('i', [1121 1122], 'Save', true);
    %   branchRegistration('i', [1121 1122], 'ShiftVitread', true);
    %
    % History:
    %	22Jan2018 - SSP
    %   7Sept2018 - SSP - input parsing, vitread shift, plotting zero lines
    % ---------------------------------------------------------------------

    source = validateSource(source);
    
    ip = inputParser();
    ip.CaseSensitive = false;
    addParameter(ip, 'Save', false, @islogical);
    addParameter(ip, 'View', true, @islogical);
    addParameter(ip, 'ShiftVitread', false, @islogical);
    parse(ip, varargin{:});
    writeToLog = ip.Results.Save;
    visualize = ip.Results.View;
    shiftVitread = ip.Results.ShiftVitread;

	source = validateSource(source);
	template = ['/Locations?$filter=Z eq %u and TypeCode eq 1',...
				'&$select=ID,ParentID,VolumeX,VolumeY,Z'];
	propNames = {'ID', 'ParentID', 'X', 'Y', 'Z'};

	% Query and process data from vitread (min) section
	data = readOData([getServiceRoot(source),...
		sprintf(template, min(sections))]);
    value = cat(1, data.value{:});
	vitread = struct2table(value);
	vitread.Properties.VariableNames = propNames;
	vitread = catchFalse(vitread);

	% Query and process data from sclerad (max) section 
	data = readOData([getServiceRoot(source),...
		sprintf(template,  max(sections))]);
    value = cat(1, data.value{:});
	sclerad = struct2table(value);
	sclerad.Properties.VariableNames = propNames;
	sclerad = catchFalse(sclerad);

	% Get the IDs
	vitreadIDs = unique(vitread.ParentID);
	scleradIDs = unique(sclerad.ParentID);

	% Remove IDs in sclerad that aren't in vitread
	invalid = setdiff(scleradIDs, vitreadIDs);
	if ~isempty(invalid)
		sclerad(ismember(sclerad.ParentID, invalid), :) = [];
	end
	fprintf('Analyzing %u locations from %u neurons\n',...
		height(sclerad), numel(scleradIDs)-numel(invalid));

	linkQuery = [getServiceRoot(source),...
		'Locations(%u)?$select=ID&$expand=LocationLinksA',...
		'($select=A,B)'];

    % Calculate offsets: SCLERAD - VITREAD
    offsetList = [];
    for i = 1:height(sclerad)
        data = readOData(sprintf(linkQuery, sclerad.ID(i)));
        locationLinksA = cat(1, data.LocationLinksA{:});
        for j = 1:numel(locationLinksA)
            % Get the vitread location ID and 
            linkedID = locationLinksA(j).B;
            linkedLoc = vitread{vitread.ID == linkedID,{'X', 'Y'}};
            if ~isempty(linkedLoc)
                if shiftVitread
                    xyOffset = linkedLoc - sclerad{i, {'X', 'Y'}};
                else
                    xyOffset = sclerad{i, {'X', 'Y'}} - linkedLoc;
                end
                offsetList = [offsetList; xyOffset]; %#ok
            end
        end
    end

    printStat(offsetList(:,1)');
    printStat(offsetList(:,2)');

    % Take the median (horizontally branching neurons will register as
    % large outliers, which influence the mean more than the median)
    xyOffset = median(offsetList);

    if visualize
        ax = axes('Parent', figure());
        hold(ax, 'on');
        plot(ax, offsetList(:,1), offsetList(:,2),...
            '.b', 'MarkerSize', 10);
        plot(ax, xyOffset(1), xyOffset(2),...
            'or', 'MarkerFaceColor', 'r');
        title(ax, sprintf('X = %.3g and Y = %.3g', xyOffset));
        x = get(ax, 'XLim'); y = get(ax, 'YLim');
        plot(ax, [x(1), x(2)], [0, 0], '--', 'Color', [0.5, 0.5, 0.5]);
        plot(ax, [0, 0], [y(1), y(2)], '--', 'Color', [0.5, 0.5, 0.5]);
    end

    if writeToLog
        fName = ['XY_OFFSET_', upper(source), '.txt'];
        fPath = [fileparts(fileparts(fileparts(mfilename('fullpath')))),...
            filesep, 'data', filesep, fName];
        data = dlmread(fPath);
        if shiftVitread
            Z = max(sections);
            data(Z:end, 2) = data(Z:end, 2) + xyOffset(1);
            data(Z:end, 3) = data(Z:end, 3) + xyOffset(2);
        else
            Z = min(sections);
            data(1:Z, 2) = data(1:Z, 2) + xyOffset(1);
            data(1:Z, 3) = data(1:Z, 3) + xyOffset(2);
        end
        dlmwrite(fPath, data);
    end
end

function T = catchFalse(T)
    % CATCHFALSE  Remove annotations with X/Y = 0
    T(T.X == 0 | T.Y == 0, :) = [];
end