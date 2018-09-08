classdef DendriteDiameter < sbfsem.analysis.NeuronAnalysis
    % PRIMARYDENDRITEDIAMETER
    % See analyzeDS.m for information on use
    %
    % Syntax:
    %   x = sbfsem.analysis.DendriteDiameter(neuron);
    %
    % Parameters:
    %	neuron : neuron object
    %   nbins  : optional, integer 
    %   	Number of bins for histogram (if empty, Matlab decides)
    %	dim : optional, integer	
    %       Compute distance in two (XY) or three (XYZ) dimensions
    %	ind 	    []	    rows to remove (axon, soma)
    %	graph : optional, logical	
    %   	Automatically plot results (default = False)
    %	search : optional, vector		
    %       Primary dendrite search window (default = [2 5])
    %
    % Returns:
    %	d 			structure containing statistics
    %
    % Notes: 
    %   The default bin count set by Matlab is typically an underestimate
    % 	for our purposes. I would suggest experimenting with the number of 
    % 	bins, through the `nbins` parameter (see below).
    %
    %   Especially for wide-field neurons, computing distance based on 2 
    %   dimensions is preferable, given the low resolution in the Z axis
    %   (70/90nm in the Z vs 5nm in the XY)
    %
    % Examples:
    %   c4781 = Neuron(4781, 't');
    %   x = sbfsem.analysis.DendriteDiameter(c4781);
    %   x.plot();
    %	% Try a higher bin count
    %	x = sbfsem.analysis.DendriteDiameter(c4781, 'nbins', 20)
    %
    %   See tutorial_DendriteDiameter.m for details
    %
    %
    % See also: 
    %   sbfsem.analysis.NeuronAnalysis.m, analyzeDS.m
    %
    % 25Aug2017 - SSP - created from analyzeDS.m
    % 2Aug2018 - SSP - renamed to DendriteDiameter
    %                  updated to make more user-friendly
    % --------------------------------------------------------------------
    
    properties (Constant = true, Hidden = true)
        DisplayName = 'DendriteDiameter';
    end
    
    methods
        function obj = DendriteDiameter(neuron, varargin)
            validateattributes(neuron, {'NeuronAPI'}, {});
            obj@sbfsem.analysis.NeuronAnalysis(neuron);
            
            obj.doAnalysis(varargin{:});
        end
        
        function doAnalysis(obj, varargin)
            ip = inputParser();
            ip.CaseSensitive = false;
            addParameter(ip, 'dim', 2, @(x) ismember(x, [2 3]));
            addParameter(ip, 'ind', [], @isvector);
            addParameter(ip, 'nbins', [], @isnumeric);
            addParameter(ip, 'search', [2 5], @isvector);
            parse(ip, varargin{:});
            nbins = ip.Results.nbins;
            searchBins = ip.Results.search(1):ip.Results.search(2);
            
            % Get the soma location
            soma = getSomaXYZ(obj.target);
            % Remove rows for soma/axon
            T = obj.target.getCellNodes;
            if ~isempty(ip.Results.ind)
                T(ip.Results.ind,:) = [];
            end
            % Get the remaining locations
            xyz = T.XYZum;
            
            % Get the distance of each annotation from the soma
            if ip.Results.dim == 2
                % Remove Z-axis
                xyz = xyz(:, 1:2);
                soma = soma(:, 1:2);
                somaDist = fastEuclid2d(soma, xyz);
            else
                somaDist = fastEuclid3d(soma, xyz);
            end
            
            fprintf('soma distances range from %.2f to %.2f microns\n',...
                min(somaDist), max(somaDist));
            
            % Create a histogram of soma distances
            if isempty(nbins)
                [n, edges, bins] = histcounts(somaDist);
                fprintf('Using %u bins\n', numel(n));
            else
                [n, edges, bins] = histcounts(somaDist, nbins);
            end
            
            % Get the dendrite sizes
            dendrite = T.Rum;
            
            % Prevent splitapply error for empty bins
            emptyBins = find(n == 0);
            % Make sure each bin is represented by setting empty bins to 0
            if ~isempty(emptyBins)
                % Lots of empty bins is generally not a good sign
                fprintf('Found %u empty bins\n', numel(emptyBins));
                bins = cat(1, bins, emptyBins');
                dendrite = cat(1, dendrite, zeros(numel(emptyBins)));
            end
            
            % Compute dendrite size stats per distance bin
            h.counts = n';
            h.binCenters = edges(2:end)' - (edges(2)-edges(1))/2;
            h.avg = splitapply(@mean, dendrite, bins);
            h.std = splitapply(@std, dendrite, bins);
            h.sem = splitapply(@sem, dendrite, bins);
            h.median = splitapply(@median, dendrite, bins);
            h.n = sum(h.counts);
                        
            % Save to object
            obj.data = h;

            % Save the params for later reference
            h.params.nbins = ip.Results.nbins;
            h.params.dim = ip.Results.dim;
            h.params.ind = ip.Results.ind;           
            
            % Print some results
            obj.report()
            
        end

        function report(obj, includeSoma)
            % REPORT
            %
            % includeSoma : optional, logical
            %   If true, includes soma bin in statistics (default = false)
            % 
            % Examples:
            %   obj.report()
            %   % Include soma bin
            %   obj.report(true);

            if nargin < 2
                includeSoma = false;
            end

            fprintf('--- c%u ---\n', obj.target.ID);
            if includeSoma
                fprintf('** Stats include soma bin **\n')
                ind = 1;
            else
                fprintf('** Stats do not include soma bin **\n')
                ind = 2;
            end

            % sprintf('search window = %.2f to %.2f\n', obj.data.searchWindow);
            fprintf('analysis includes %u annotations\n',...
                sum(obj.data.counts(ind:end)));
            fprintf('mean radius = %.2f +- %.2f (SEM)\n',...
                mean(obj.data.avg(ind:end)), mean(obj.data.sem(ind:end)));
            fprintf('mean radius = %.2f +- %.2f (SD)\n',...
                mean(obj.data.avg(ind:end)), mean(obj.data.std(ind:end)));
            fprintf('median diameter = %.4f\n',...
                mean(2*obj.data.median(ind:end)));
        end

        function T = table(obj)
            % TABLE
            % Returns data as a table
            warning('off', 'MATLAB:structOnObject');
            S = struct(obj.data);
            S = rmfield(S, 'n');
            T = struct2table(S);
        end
        
        function fh = plot(obj, varargin)
            % VISUALIZE  Plot the analysis results
            %
            % Optional key/value inputs:
            %   SD : optional, logical
            %       Error bars show on SD rather than SEM (default = false)
            %   median : optional, logical
            %       Plot the median values too (default = false)
            %   includeSoma : optional, logical
            %       Plot the soma bin (default = true)
            %       
            % ----------------------------------------------------
            ip = inputParser();
            ip.CaseSensitive = false;
            addParameter(ip, 'SD', false, @islogical);
            addParameter(ip, 'Median', false, @islogical);
            addParameter(ip, 'includeSoma', true, @islogical);
            parse(ip, varargin{:});
            showMedian = ip.Results.Median;

            if ip.Results.includeSoma
                ind = 1;
            else
                ind = 2;
            end

            fh = figure('Name', sprintf('c%u dendrite analysis',...
                obj.target.ID));
            ax = axes('Parent', fh,...
                'Box', 'off', 'TickDir', 'out');
            hold on;

            if ip.Results.SD
                errorMetric = obj.data.std(ind:end);
                legendStr = 'mean (SD)';
            else
                errorMetric = obj.data.sem(ind:end);
                legendStr = 'mean (SEM)';
            end
            
            % Plot the median, if necessary
            if showMedian
                plot(obj.data.binCenters(ind:end), obj.data.median(ind:end),...
                    '--b', 'LineWidth', 1.5);
            end

            % Plot the mean and err
            shadedErrorBar(obj.data.binCenters(ind:end), obj.data.avg(ind:end),...
                errorMetric, 'lineprops', {'-k', 'LineWidth', 2});

            if showMedian
                legend(ax, 'median', legendStr);
            else
                legend(ax, legendStr);
            end
            set(legend, 'EdgeColor', 'w', 'FontSize', 12);

            xlabel(ax, 'distance from soma (microns)');
            ylabel(ax, 'avg dendrite diameter (microns)');
            title(ax, sprintf('c%u', obj.target.ID));
            set(ax, 'FontSize', 14);
            yLim = get(ax, 'YLim');
            set(ax, 'YLim', [0, yLim(2)]);
        end
    end
end