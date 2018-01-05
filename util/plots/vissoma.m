function fh = vissoma(xyr, varargin)
	% plot soma using viscircles
	%
	% INPUT: 
	%		xyr 					[x, y, radius]
	%	OPTIONAL: 
	%		ax 						existing axesHandle
	%		co 						edgecolor
	%		lw 						linewidth
	% OUTPUT: 
	%		fh 			figureHandle
	%
	% 29Jul2017 - SSP - created



	ip = inputParser();
	ip.CaseSensitive = false;
	ip.addParameter('ax', [], @ishandle);
	ip.addParameter('Color', [0 0 0], @isnumeric);
	ip.addParameter('LineWidth', 1, @isnumeric);
	ip.parse(varargin{:});
	ax = ip.Results.ax;

	if strcmp(class(xyr), 'Neuron')
		row = neuron.getSomaRow();
		xyr = [row.XYZum(1:2), row.Rum];
	end

	if isempty(ax)
		fh = figure();
		ax = gca;
	else
		fh = ax.Parent;
	end

	viscircles(ax, xyr(1:2), xyr(3),...
		'LineWidth', ip.Results.lw,... 
		'EdgeColor', ip.Results.co);

	hold on; axis equal;