function s = parseConnectivity(connectivityFile)
	% parse connectivity json file
	%
	% 21Jun2017 - SSP - created
	% 22Jun2017 - fixed edge value error
	% 5Jul2017 - rewrote for table layout

	if ischar(connectivityFile) && strcmp(connectivityFile(end-3:end), 'json')
		fprintf('parsing with loadjson.m...');
		hops = loadjson(connectivityFile);
		fprintf('parsed\n');
	elseif isstruct(connectivityFile) % output from loadjson
		hops = connectivityFile;
	else
		error('input file name as string or struct from loadjson()');
	end

	s.fileName = hops.graph.attributes.file{2};
	s.parseDate = datestr(now);
	s.tulipData.numEdges = hops.graph.edgesNumber;
	s.tulipData.numNodes = hops.graph.nodesNumber;
	s.contacts = hops.graph.edges + 1;

	% get all the edge fieldnames
	s.edgeList = fieldnames(hops.graph.properties.LinkedStructures.edgesValues);
	% get the node names
	s.nodeList = fieldnames(hops.graph.properties.ID.nodesValues);

	% some of these are redundant. condense later
	Source = [];
	Target = [];
	Dir = [];
	ParentIDs = [];
	EdgeUUID = cell(1,1);
	EdgeName = cell(1,1);
	EdgeType = cell(1,1);
	Loop = [];

	NodeLabel = cell(1,1);
	NodeUUID = cell(1,1);
	CellID = [];

	for ii = 1:length(s.nodeList)
		nodeName = s.nodeList{ii};
		NodeUUID = cat(1, NodeUUID, nodeName);
		CellID = cat(1, CellID, str2double(hops.graph.properties.ID.nodesValues.(nodeName)));
		NodeLabel = cat(1, NodeLabel, char(hops.graph.properties.viewLabel.nodesValues.(nodeName)));
	end % nodeList loop

	for ii = 1:length(s.edgeList)
		edgeName = char(s.edgeList{ii});
		% s.props.enameMap(edgeName) = edgeName;
		EdgeUUID= cat(1, EdgeUUID, edgeName);

		tmp = hops.graph.properties.LinkedStructures.edgesValues.(edgeName);
		tmp = regexp(tmp, '   ', 'split');
		if isempty(tmp{1})
			numVal = 2:length(tmp);
		else
			numVal = 1:length(tmp);
		end
		edgeVal = zeros(length(numVal),2);

		for jj = 1:length(numVal)
			tmp{numVal(jj)} = deblank(tmp{numVal(jj)});
			x = regexp(tmp{numVal(jj)}, '->', 'split');
			x = cellfun(@str2double, x);
			edgeVal(jj,:) = x;
		end
		% s.props.evalMap(edgeName) = edgeVal;
		ParentIDs = cat(1, ParentIDs, x);

		% s.props.etypeMap(edgeName) = hops.graph.properties.edgeType.edgesValues.(edgeName);
		EdgeType = cat(1, EdgeType, hops.graph.properties.edgeType.edgesValues.(edgeName));
		EdgeName = cat(1, EdgeName, getLocalName(hops.graph.properties.viewLabel.edgesValues.(edgeName)));

		Source = cat(1, Source, str2double(hops.graph.properties.Source.edgesValues.(edgeName)));
		Target = cat(1, Target, str2double(hops.graph.properties.Target.edgesValues.(edgeName)));

		if isfield(hops.graph.properties.IsLoop, 'edgesValues')
			if isfield(hops.graph.properties.IsLoop.edgesValues, edgeName)
				Loop = cat(1, Loop, 1);
			else
				Loop = cat(1, Loop, 0);
			end
		end

		if strcmp(hops.graph.properties.Directional.edgesValues.(edgeName), 'True')
			Dir = cat(1, Dir, 1);
		else
			Dir = cat(1, Dir, 0);
		end
	end % edgeList loop

	% probably a better way to do this but oh well
	EdgeUUID(1,:) = [];
	EdgeName(1,:) = [];
	EdgeType(1,:) = [];
	NodeLabel(1,:) = [];
	NodeUUID(1,:) = [];

	% make the output tables
	s.edgeTable = table(Source, Target, Dir, EdgeName, ParentIDs, EdgeType, EdgeUUID);
	s.nodeTable = table(CellID, NodeLabel, NodeUUID);

