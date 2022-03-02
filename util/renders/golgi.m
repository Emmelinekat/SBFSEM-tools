function ax = golgi(neuron, varargin)
    % GOLGI
    %
    % Description:
    %   Plot a neuron in a golgi-like flatmount
    %
    % Syntax:
    %   ax = golgi(neuron, ax)
    %
    % Inputs:
    %   neuron      Neuron object
    % Optional key/value inputs:
    %   Ax          Handle to existing axes (default = new figure)
    %   Invert      Invert colors (default = false)
    %   Color       Render color (default = 'k'/'w', depending on invert)
    %
    % Outputs:
    %   ax          Handle to axes 
    %
    % History:
    %   10Feb2019 - SSP
    %   5Apr2019 - SSP - Added invert figure option, input parsing
    %   5May2019 - SSP - Added color argument
    % ---------------------------------------------------------------------

    ip = inputParser();
    ip.CaseSensitive = false;
    ip.KeepUnmatched = true;
    addParameter(ip, 'Ax', [], @ishandle);
    addParameter(ip, 'Invert', false, @islogical);
    addParameter(ip, 'Color', [], @(x) ischar(x) || isnumeric(x));
    addParameter(ip, 'FaceAlpha', 1, @isnumeric);
    parse(ip, varargin{:});
    
    invertFigure = ip.Results.Invert;
    if isempty(ip.Results.Ax)
        ax = axes('Parent', figure());
    else
        ax = ip.Results.Ax;
        delete(findall(ax, 'Type', 'light'));
    end
    hold(ax, 'on');
    
    if invertFigure
        ax.Color = 'k'; ax.Parent.Color = 'k';
    end
    
    if invertFigure && isempty(ip.Results.Color)
        neuron.render('ax', ax, 'FaceColor', 'w', ip.Unmatched);
    elseif ~invertFigure && isempty(ip.Results.Color)
        neuron.render('ax', ax, 'FaceColor', 'k', ip.Unmatched);
    else
        neuron.render('ax', ax, 'FaceColor', ip.Results.Color, ip.Unmatched);
    end
    
    view(ax, 0, 90);
    hideAxes();
    