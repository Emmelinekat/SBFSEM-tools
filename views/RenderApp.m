classdef RenderApp < handle
    % RENDERAPP
    %
    % Description:
    %   UI for viewing renders and creating scenes for figures
    %
    % Constructor:
    %   obj = RenderApp(source);
    %
    % Example:
    %   RenderApp('i');
    %
    % Todo:
    %   - Check for duplicate neurons
    %   - Synapses
    %   - Legend colors
    %   - Add neuron input validation
    %
    % See also:
    %   GRAPHAPP, IMAGESTACKAPP, IPLDEPTHAPP, NEURON
    %
    % History:
    %   5Jan2018 - SSP
    %   19Jan2018 - SSP - menubar, replaced table with checkbox tree
    %   12Feb2018 - SSP - IPL boundaries and scale bars
    %   26Apr2018 - SSP - Added NeuronCache option to Import menu
    %   7Oct2018 - SSP - New context tab for importing markers, cones
    % ---------------------------------------------------------------------

    properties (SetAccess = private)
        neurons             % Neuron objects
        IDs                 % IDs of neuron objects
        source              % Volume name
        volumeScale         % Volume dimensions (nm/pix)
        mosaic              % Cone mosaic (empty until loaded)
        iplBound            % IPL Boundary structure (empty until loaded)
        vessels             % Blood vessels (empty until loaded)
    end

    properties (Access = private, Hidden = true, Transient = true)
        % UI handles
        figureHandle        % Parent figure handle
        ui                  % UI panel handles
        ax                  % Render axis
        neuronTree          % Checkbox tree
        lights              % Light handles
        scaleBar            % Scale bar (empty until loaded)

        % UI properties
        isInverted          % Is axis color inverted

        % UI view controls
        azel = [-37.5, 30];
        zoomFac = 0.9;
        panFac = 0.02;

        % XY offset applied to volume on neuron import
        xyOffset = [];      % Loaded on first use

        % Transformation to XY offsets
        transform = sbfsem.core.Transforms.Viking;
    end

    properties (Constant = true, Hidden = true)
        DEFAULTALPHA = 0.6;
        SYNAPSES = false;
        SOURCES = {'NeitzTemporalMonkey','NeitzInferiorMonkey','MarcRC1'};
        CACHE = [fileparts(fileparts(mfilename('fullname'))), filesep, 'data'];
    end

    methods
        function obj = RenderApp(source)
            % RENDERAPP
            %
            % Description:
            %   Constructor, opens UI and optional volume select UI
            %
            % Optional inputs:
            %   source          Volume name or abbreviation (char)
            %
            % Note:
            %   If no volume name is provided, a listbox of available
            %   volumes will appear before the main UI opens
            % -------------------------------------------------------------
            if nargin > 0
                obj.source = validateSource(source);
            else
                [selection, selectedSource] = listdlg(...
                    'PromptString', 'Select a source:',...
                    'Name', 'RenderApp Source Selection',...
                    'SelectionMode', 'single',...
                    'ListString', obj.SOURCES);
                if selectedSource
                    obj.source = obj.SOURCES{selection};
                    fprintf('Running with %s\n', obj.source);
                else
                    warning('No source selected... exiting');
                    return;
                end
            end

            obj.neurons = containers.Map();
            obj.iplBound = struct();
            obj.iplBound.gcl = [];
            obj.iplBound.inl = [];
            obj.vessels = [];
            obj.createUI();

            obj.volumeScale = getODataScale(obj.source);
            obj.isInverted = false;
            obj.xyOffset = [];
        end
    end

    % Callback methods
    methods (Access = private)
        function onAddNeuron(obj, ~, ~)
            % No input detected
            if isempty(obj.ui.newID.String)
                return;
            end

            % Separate neurons by commas
            str = deblank(obj.ui.newID.String);
            if nnz(isletter(deblank(obj.ui.newID.String))) > 0
                warning('Neuron IDs = integers separated by commas');
                return;
            end
            str = strsplit(str, ',');

            % Clear out accepted input string so user doesn't accidentally
            % add the neuron twice while program runs.
            set(obj.ui.newID, 'String', '');

            % Import the new neuron(s)
            for i = 1:numel(str)
                newID = str2double(str{i});
                obj.updateStatus(sprintf('Adding c%u', newID));
                success = obj.addNeuron(newID);
                if ~success
                    fprintf('Skipped c%u\n', newID);
                    continue;
                end

                newColor = findall(obj.ax, 'Tag', obj.id2tag(newID));
                newColor = get(newColor(1), 'FaceColor');

                obj.addNeuronNode(newID, newColor);
                obj.updateStatus();
                % Update the plot after each neuron imports
                drawnow;
            end
            h = findobj(obj.figureHandle, 'Type', 'uitable');
            data = get(h, 'Data');
            names = get(h, 'RowName');
            for i = 1:3
                if data{i,1}
                    set(obj.ax, [names{i}, 'Lim'], [data{i,2}, data{i,3}]);
                end
            end
        end

        function onToggleGrid(obj, src, ~)
            % TOGGLEGRID  Show/hide the grid
            if src.Value == 1
                grid(obj.ax, 'on');
            else
                grid(obj.ax, 'off');
            end
        end

        function onToggleAxes(obj, ~, ~)
            % ONTOGGLEAXES  Show/hide axes
            if sum(obj.ax.XColor) == 3
                newColor = [0 0 0];
            else
                newColor = [1 1 1];
            end
            set(obj.ax, 'XColor', newColor,...
                'YColor', newColor, 'ZColor', newColor);
        end

        function onSetRotation(obj, src, ~)
            % ONSETROTATION
            switch src.Tag
                case 'XY1'
                    view(obj.ax, 2);
                case 'XY2'
                    view(0, -90);
                case 'YZ'
                    view(90, 0);
                case 'XZ'
                    view(obj.ax, 0, 0);
                case '3D'
                    view(obj.ax, 3);
            end
        end

        function toggleSurface(obj, name, value)
            if value             
                switch name
                    case 'GCL'
                        obj.iplBound.gcl.plot('ax', obj.ax);
                    case 'INL'
                        obj.iplBound.inl.plot('ax', obj.ax);
                end
            else
                obj.iplBound.inl.deleteFromScene(obj.ax);
                set(findobj(obj.figureHandle, 'Tag', 'IPL'),...
                    'Value', 0);
                set(findobj(obj.figureHandle, 'Tag', 'GCL'),...
                    'Value', 0);
            end
        end

        function onToggleLights(obj, src, ~)
            % ONTOGGLELIGHTS  Turn lighting on/off

            if src.Value == 0
                set(findall(obj.ax, 'Type', 'patch'),...
                    'FaceLighting', 'gouraud');
            else
                set(findall(obj.ax, 'Type', 'patch'),...
                    'FaceLighting', 'none');
            end
        end

        function onToggleInvert(obj, ~, ~)
            % ONINVERT  Invert figure colors
            if ~obj.isInverted
                bkgdColor = 'k'; frgdColor = 'w';
                set(obj.ax, 'GridColor', [0.85, 0.85, 0.85]);
                obj.isInverted = true;
            else
                bkgdColor = 'w'; frgdColor = 'k';
                set(obj.ax, 'GridColor', [0.15 0.15 0.15]);
                obj.isInverted = true;
            end
            set(obj.ax, 'Color', bkgdColor,...
                'XColor', frgdColor,...
                'YColor', frgdColor,...
                'ZColor', frgdColor);
            set(obj.ax.Parent,...
                'BackgroundColor', bkgdColor);
        end

        function onExportImage(obj, src, ~)
            % ONEXPORTIMAGE  Save renders as an image

            % Export figure to new window without uicontrols
            newAxes = obj.exportFigure();
            set(newAxes.Parent, 'InvertHardcopy', 'off');

            % Open a save dialog to get path, name and extension
            [fName, fPath] = uiputfile(...
                {'*.jpeg'; '*.png'; '*.tiff'},...
                'Save image as a JPEG, PNG or TIFF');

            % Catch when user cancels out of save dialog
            if isempty(fName) || isempty(fPath)
                return;
            end

            % Save by extension type
            switch fName(end-2:end)
                case 'png'
                    exten = '-dpng';
                case 'peg'
                    exten = '-djpeg';
                case 'iff'
                    exten = '-dtiff';
            end

            if isempty(strfind(src.Label, 'high res'))
                print(newAxes.Parent, [fPath, fName], exten);
            else
                print(newAxes.Parent, [fPath, fName], exten, '-r600');
            end
            fprintf('Saved as: %s\n', [fPath, fName]);
            delete(newAxes.Parent);
        end

        function onExportCollada(obj, ~, ~)
            % ONEXPORTCOLLADA  Export the scene as a .dae file
            % See also: EXPORTSCENEDAE

            % Prompt user for file name and path
            [fName, fPath] = uiputfile('*.dae', 'Save as');
            % Catch when user cancels out of save dialog
            if isempty(fName) || isempty(fPath)
                return;
            end
            exportSceneDAE(obj.ax, [fPath, fName]);
        end

        function onExportNeuron(obj, ~, ~)
            % ONEXPORTNEURON  Export Neuron objects to base workspace

            tags = obj.neurons.keys;
            for i = 1:numel(tags)
                assignin('base', sprintf('c%u', tags{i}),...
                    obj.neurons(tags{i}));
            end
        end

        function onExportFigure(obj, ~, ~)
            % ONEXPORTFIGURE  Copy figure to new window
            obj.exportFigure();
        end
        
        function onKeyPress(obj, ~, eventdata)
            % ONKEYPRESS  Control plot view with keyboard
            %
            % See also: AXDRAG
            switch eventdata.Character
                case 'h' % help menu
                    helpdlg(obj.getInstructions, 'Navigation Instructions');
                case 28 % Rotate (azimuth -)
                    obj.azel(1) = obj.azel(1) - 5;
                case 30 % Rotate (elevation -)
                    obj.azel(2) = obj.azel(2) - 5;
                case 31 % Rotate (elevation +)
                    obj.azel(2) = obj.azel(2) + 5;
                case 29 % Rotate (azimuth +)
                    obj.azel(1) = obj.azel(1) + 5;
                case 'a' % Pan (x+)
                    x = get(obj.ax, 'XLim');
                    set(obj.ax, 'XLim', x + obj.panFac * diff(x));
                case 'd' % Pan (x-)
                    x = get(obj.ax, 'XLim');
                    set(obj.ax, 'XLim', x - obj.panFac * diff(x));
                case 'e' % Pan (y+)
                    y = get(gca, 'YLim');
                    set(obj.ax, 'YLim', y + obj.panFac * diff(y));
                case 'q' % Pan (y-)
                    y = get(gca, 'YLim');
                    set(obj.ax, 'YLim', y - obj.panFac * diff(y));
                case 'w' % pan (z+)
                    z = get(obj.ax, 'ZLim');
                    set(obj.ax, 'ZLim', z + obj.panFac * diff(z));
                case 's' % pan (z-)
                    z = get(obj.ax, 'ZLim');
                    set(obj.ax, 'ZLim', z - obj.panFac * diff(z));
                case {'z', 'Z'} % Zoom
                    % SHIFT+Z changes zoom direction
                    if eventdata.Character == 'Z'
                        obj.zoomFac = 1/obj.zoomFac;
                    end

                    x = get(obj.ax, 'XLim');
                    y = get(obj.ax, 'YLim');

                    set(obj.ax, 'XLim',...
                        [0, obj.zoomFac*diff(x)] + x(1)...
                        + (1-obj.zoomFac) * diff(x)/2);
                    set(obj.ax, 'YLim',...
                        [0, obj.zoomFac*diff(y)] + y(1)...
                        + (1-obj.zoomFac) * diff(y)/2);
                case 'm' % Return to original dimensions and view
                    view(obj.ax, 3);
                    axis(obj.ax, 'tight');
                case 'c' % Copy the last click location
                    % Don't copy position if no neurons are plotted
                    if isempty(obj.neurons)
                        return;
                    end

                    % Convert microns to Viking pixel coordinates
                    posMicrons = mean(get(obj.ax, 'CurrentPoint')); %um
                    um2pix = obj.volumeScale/1e3; % nm/pix -> um/pix
                    posViking = posMicrons./um2pix; % pix

                    % Reverse the xyOffset applied on Neuron creation
                    if strcmp(obj.source, 'NeitzInferiorMonkey')
                        if isempty(obj.xyOffset)
                            dataDir = fileparts(fileparts(mfilename('fullpath')));
                            offsetPath = [dataDir,filesep,'data',filesep,...
                                'XY_OFFSET_', upper(obj.source), '.txt'];
                            obj.xyOffset = dlmread(offsetPath);
                        end
                        posViking(3) = round(posViking(3));
                        appliedOffset = obj.xyOffset(posViking(3), 1:2);
                        posViking(1:2) = posViking(1:2) - appliedOffset;
                    end

                    % Format to copy into Viking
                    locationStr = obj.formatCoordinates(posViking);
                    clipboard('copy', locationStr);
                    fprintf('Copied to clipboard:\n %s\n', locationStr);
                otherwise % Unregistered key press
                    return;
            end
            view(obj.ax, obj.azel);
        end

        function openHelpDlg(obj, src, ~)
            % OPENHELPDLG  Opens instructions dialog

            switch src.Tag
                case 'navigation'
                    helpdlg(obj.getInstructions, 'Navigation Instructions');
                case 'import'
                    str = sprintf(['NEURONS:\n',...
                        'Import neurons by typing in the cell ID(s)\n',...
                        'Input multiple neurons by separating their ',...
                        'IDs by commas\n',...
                        '\nCONE MOSAIC:\n',...
                        '\nIPL BOUNDARIES:\n',...
                        'Add INL-IPL and IPL-GCL Boundaries to the',...
                        'current render. Note: for now these cannot be',...
                        'updated once in place\n']);
                    helpdlg(str, 'Import Instructions');
                case 'scalebar'
                    str = sprintf([...
                        'Add a ScaleBar through the Render Objects menu',...
                        '\nOpening dialog will ask for the XYZ ',...
                        'coordinates of the origin, the scale bar ',...
                        ' length and the units (optional)\n',...
                        '\nOnce in the figure, right click on the ',...
                        'scalebar to change properties:\n',...
                        '- ''Modify ScaleBar'' reopens the origin, bar',...
                        'size and units dialog box.\n',...
                        '- ''Text Properties'' and ''Line Properties''',...
                        ' opens the graphic object property menu where ',...
                        'you can change font size, color, width, etc\n']);
                    helpdlg(str, 'ScaleBar Instructions');
            end
        end

        function onSetNextColor(obj, src, ~)
            % ONSETNEXTCOLOR  Open UI to choose color, reflect change

            newColor = selectcolor('hCaller', obj.figureHandle);

            if ~isempty(newColor) && numel(newColor) == 3
                set(src, 'BackgroundColor', newColor);
            end
        end

        function onChangeColor(obj, ~, evt)
            % ONCHANGECOLOR  Change a render's color

            newColor = selectcolor('hCaller', obj.figureHandle);

            if ~isempty(newColor) && numel(newColor) == 3
                set(findall(obj.ax, 'Tag', evt.Source.Tag),...
                    'FaceColor', newColor);
            end
        end

        function onOpenGraphApp(obj, ~, evt)
            % ONOPENVIEW  Open a single neuron analysis view
            % See also:
            %   GRAPHAPP

            neuron = obj.neurons(num2str(obj.tag2id(evt.Source.Tag)));
            obj.updateStatus('Opening view');
            GraphApp(neuron);
            obj.updateStatus('');
        end

        function onAddCones(obj, src, ~)
            % ONIMPORTCONES
            % See also: SBFSEM.BUILTIN.CONEMOSAIC, SBFSEM.CORE.CLOSEDCURVE
            if isempty(obj.mosaic)
                obj.updateStatus('Loading mosaic...');
                obj.mosaic = sbfsem.builtin.ConeMosaic.fromCache('i');
                obj.updateStatus('');
            end

            obj.toggleCones(src.Tag(4:end), src.Value);
        end
        
        function onAddBloodVessels(obj, src, ~)
            % ONADDBLOODVESSELS
            % See also: SBFSEM.BUILTIN.VASCULATURE, SBFSEM.CORE.BLOODVESSEL
            
            if src.Value
                if isempty(obj.vessels)
                    obj.vessels = sbfsem.builtin.Vasculature(obj.source);
                    if ~isempty(obj.vessels.vessels)
                        obj.vessels.render('ax', obj.ax);
                    end
                else
                    set(findall(obj.figureHandle, 'Tag', 'BloodVessel'),...
                        'Visible', 'on');
                end
            else
                set(findall(obj.figureHandle, 'Tag', 'BloodVessel'),...
                    'Visible', 'off');
            end
        end

        function toggleCones(obj, coneType, value)
            if value
                obj.mosaic.plot(coneType, obj.ax, coneType);
            else
                delete(findall(gcf, 'Tag', coneType));
            end
        end

        function onUpdateNeuron(obj, ~, evt)
            % ONUPDATENEURON  Update the underlying OData and render

            % Save the view azimuth and elevation
            [az, el] = view(obj.ax);

            % Get the target ID and neuron
            ID = obj.tag2id(evt.Source.Tag);
            neuron = obj.neurons(num2str(ID));

            % Update the OData and the 3D model
            obj.updateStatus('Updating OData');
            neuron.update();
            obj.updateStatus('Updating model');
            neuron.build();
            % Save the properties of existing render and axes
            patches = findall(obj.ax, 'Tag', evt.Source.Tag);
            oldColor = get(patches, 'FaceColor');
            oldAlpha = get(patches, 'FaceAlpha');
            % Delete the old one and render a new one
            delete(patches);
            obj.updateStatus('Updating render');
            neuron.render('ax', obj.ax, 'FaceColor', oldColor,...
                'FaceAlpha', oldAlpha);
            % Return to the original view azimuth and elevation
            view(obj.ax, az, el);
            obj.updateStatus('');
        end

        function onNodeChecked(obj, ~, evt)
            % ONNODECHECKED  Toggles visibility of patches

            % The Matlab wrapper returns only selection paths, not nodes
            if isempty(evt.SelectionPaths)
                % No nodes are checked
                set(findall(obj.ax, 'Type', 'patch'), 'Visible', 'off');
            elseif numel(evt.SelectionPaths) == 1
                if strcmp(evt.SelectionPaths.Name, 'Root')
                    % All nodes are checked
                    set(findall(obj.ax, 'Type', 'patch'), 'Visible', 'on');
                else % Only one node is checked
                    set(findall(obj.ax, 'Type', 'patch'), 'Visible', 'off');
                    set(findall(obj.ax, 'Tag', evt.SelectionPaths(1).Name),...
                        'Visible', 'on');
                end
            elseif numel(evt.SelectionPaths) > 1
                % Some but not all nodes are checked
                set(findall(obj.ax, 'Type', 'patch'), 'Visible', 'off');
                for i = 1:numel(evt.SelectionPaths)
                    set(findall(obj.ax, 'Tag', evt.SelectionPaths(i).Name),...
                        'Visible', 'on');
                end
            end
        end

        function onGetSynapses(~, ~, ~)
            % ONGETSYNAPSES  neuron-specific uicontextmenu callback
            warningdlg('Not yet implemented!');
            return;
        end

        function onRemoveNeuron(obj, ~, evt)
            % ONREMOVENEURON  Callback to trigger neuron removal

            if numel(obj.neuronTree.SelectedNodes) ~= 1
                warning('More than one node selected');
                return
            else
                node = obj.neuronTree.SelectedNodes;
            end
            node.UIContextMenu = [];
            % Get the neuron ID
            ID = obj.tag2id(evt.Source.Tag);
            obj.removeNeuron(ID, node);
        end

        function onSetTransparency(obj, src, evt)
            % ONSETTRANSPARENCY  Change patch face alpha

            if isempty(src.Tag)
                % Apply to all neurons (from toolbar)
                newAlpha = str2double(src.Label);
                set(findall(obj.ax, 'Type', 'patch'),...
                    'FaceAlpha', newAlpha);
            elseif strcmp(src.Tag, 'DefaultAlpha')
                % Apply to all neurons (from popup menu)
                newAlpha = str2double(src.String{src.Value});
                set(findall(obj.ax, 'Type', 'patch'),...
                    'FaceAlpha', newAlpha);
            elseif strcmp(src.Tag, 'SurfAlpha')
                newAlpha = str2double(src.String{src.Value});
                set(findall(obj.ax, 'Type', 'surface'),...
                    'FaceAlpha', newAlpha);
            else
                % Apply to a single neuron
                newAlpha = str2double(src.Label);
                set(findall(obj.ax, 'Tag', evt.Source.Tag),...
                    'FaceAlpha', newAlpha);
            end
        end

        function onSetLimits(obj, src, evt)
            % ONSETLIMITS
            data = src.Data;
            ind = evt.Indices;
            % Whether to use custom or auto axis limits
            tof = data(ind(1), 1);
            % Get the axis name
            str = [src.RowName{ind(1)}, 'Lim'];
            if tof{1}
                set(obj.ax, str, [data{ind(1), 2}, data{ind(1), 3}]);
            elseif ind(2) == 1
                axis(obj.ax, 'tight');
                newLimit = get(obj.ax, str);
                data{ind(1), 2} = newLimit(1);
                data{ind(1), 3} = newLimit(2);
                src.Data = data;
            end
        end

        function onAddScaleBar(obj, src, ~)
            % ONSCALEBAR
            % See also: SBFSEM.UI.SCALEBAR3

            switch src.String
                case 'Add ScaleBar'
                    obj.scaleBar = sbfsem.ui.ScaleBar3(obj.ax);
                    src.String = 'Remove ScaleBar';
                case 'Remove ScaleBar'
                    obj.scaleBar.delete();
                    obj.scaleBar = [];
                    src.String = 'Add ScaleBar';
            end
        end

        function onAddBoundary(obj, src, ~)
            if isempty(obj.iplBound.gcl)
                obj.updateStatus('Importing boundaries');

                obj.iplBound.gcl = sbfsem.builtin.GCLBoundary(obj.source, true);
                obj.iplBound.inl = sbfsem.builtin.INLBoundary(obj.source, true);
            end
            obj.toggleSurface(src.Tag, src.Value);
        end

        function onSetTransform(obj, src, ~)
            if ~isempty(obj.neurons)
                warndlg('Changing the Transform with existing neurons is not recommended.');
            end
            switch src.String{src.Value}
                case 'Viking'
                    obj.transform = sbfsem.core.Transforms.Viking;
                case 'Local'
                    obj.transform = sbfsem.core.Transforms.SBFSEMTools;
            end
        end
        
        function onAddGap(obj, src, ~)
            if src.Value
                x = get(obj.ax, 'XLim');
                y = get(obj.ax, 'YLim');
                z = obj.volumeScale(3) * 1e-3 * 922;
                hold(obj.ax, 'on');
                patch(obj.ax, 'XData', [x; x], 'YData', [y; y]',...
                    'ZData', z+zeros(2,2), 'FaceAlpha', 0.3,...
                    'FaceColor', [0.7, 0.7, 0.7], 'Tag', 'Gap');     
            else
                delete(findall(obj.ax, 'Tag', 'Gap'));
            end
        end
    end

    methods (Access = private)
        function tf = addNeuron(obj, newID)
            % ADDNEURON  Add a new neuron and render
            % See also: NEURON
            
            try
                neuron = Neuron(newID, obj.source, obj.SYNAPSES, obj.transform);
            catch ME
                if strcmp(ME.identifier, 'MATLAB:webservices:HTTP404StatusCodeError')
                    obj.updateStatus(sprintf('c%u not found!', newID));
                    tf = false;
                    return;
                end
            end

            % Build the 3D model
            obj.updateStatus(sprintf('Rendering c%u', newID));
            neuron.build();

            % Render the neuron
            neuron.render('ax', obj.ax,...
                'FaceColor', obj.ui.nextColor.BackgroundColor,...
                'FaceAlpha', obj.DEFAULTALPHA);
            view(obj.ax, obj.azel(1), obj.azel(2));
            
            obj.neurons(num2str(newID)) = neuron;
            obj.IDs = cat(2, obj.IDs, newID);
            tf = true;
        end

        function removeNeuron(obj, ID, node)
            % REMOVENEURON  Remove a neuron from tree and figure

            % Delete from checkbox tree
            delete(node);
            % Clear out neuron data
            obj.neurons(num2str(ID)) = [];
            obj.IDs(obj.IDs == ID) = [];
            % Delete the patch from the render
            delete(findall(obj.ax, 'Tag', obj.id2tag(ID)));
        end

        function updateStatus(obj, str)
            % UPDATESTATUS  Update status text
            if nargin < 2
                str = '';
            else
                assert(ischar(str), 'Status updates must be char');
            end
            set(obj.ui.status, 'String', str);
            drawnow;
        end

        function toggleRender(obj, tag, toggleState)
            % TOGGLERENDER  Hide/show render
            set(findall(obj.ax, 'Tag', tag) , 'Visible', toggleState);
        end

        function newAxes = exportFigure(obj)
            % EXPORTFIGURE  Open figure in a new window

            newAxes = exportFigure(obj.ax);
            axis(newAxes, 'tight');
            hold(newAxes, 'on');

            % Keep only the visible components
            delete(findall(newAxes, 'Type', 'patch', 'Visible', 'off'));

            % Match the plot modifiers
            set([newAxes, newAxes.Parent], 'Color', obj.ax.Color);
            obj.setLimits(newAxes, obj.getLimits(obj.ax));
            set(newAxes.Parent, 'InvertHardcopy', 'off');
        end

        function newNode = addNeuronNode(obj, ID, ~, ~)
            % ADDNEURONNODE  Add new neuron node to checkbox tree
            % Argument four was 'hasSynapses'

            newNode = uiextras.jTree.CheckboxTreeNode(...
                'Parent', obj.neuronTree,...
                'Name', obj.id2tag(ID),...
                'Checked', true);

            c = uicontextmenu('Parent', obj.figureHandle);
            uimenu(c, 'Label', 'Update',...
                'Tag', obj.id2tag(ID),...
                'Callback', @obj.onUpdateNeuron);
            uimenu(c, 'Label', 'Remove Neuron',...
                'Tag', obj.id2tag(ID),...
                'Callback', @obj.onRemoveNeuron);
            uimenu(c, 'Label', 'Change Color',...
                'Tag', obj.id2tag(ID),...
                'Callback', @obj.onChangeColor);
            t = uimenu(c, 'Label', 'Change Transparency',...
                'Tag', obj.id2tag(ID));
            for i = 0.1:0.1:1
                uimenu(t, 'Label', num2str(i),...
                    'Tag', obj.id2tag(ID),...
                    'Callback', @obj.onSetTransparency)
            end
            uimenu(c, 'Label', 'Open GraphApp',...
                'Tag', obj.id2tag(ID),...
                'Callback', @obj.onOpenGraphApp);
            set(newNode, 'UIContextMenu', c);
        end

        function createUI(obj)
            % CREATEUI  Setup the main user interface, runs only once
            obj.figureHandle = figure(...
                'Name', 'RenderApp',...
                'Color', 'w',...
                'NumberTitle', 'off',...
                'DefaultUicontrolBackgroundColor', 'w',...
                'DefaultUicontrolFontSize', 10,...
                'DefaultUicontrolFontName', 'Segoe UI',...
                'Menubar', 'none',...
                'Toolbar', 'none',...
                'KeyPressFcn', @obj.onKeyPress);

            % Toolbar options
            obj.createToolbar();

            % Main layout with 2 panels (UI, axes)
            mainLayout = uix.HBoxFlex('Parent', obj.figureHandle,...
                'BackgroundColor', 'w');
            % Create the user interface panel
            h = uitabgroup('Parent', mainLayout);
            t1 = uitab(h, 'Title', 'Neurons');
            t2 = uitab(h, 'Title', 'Context');
            t3 = uitab(h, 'Title', 'Plot');

            obj.ui.root = uix.VBox('Parent', t1,...
                'BackgroundColor', [1 1 1],...
                'Spacing', 5, 'Padding', 5);

            ctrlLayout = uix.VBox('Parent', t3,...
                'BackgroundColor', 'w',...
                'Spacing', 5, 'Padding', 5);
            
            contextLayout = uix.VBox('Parent', t2,...
                'BackgroundColor', 'w',...
                'Spacing', 0, 'Padding', 5);

            obj.createNeuronTab();
            obj.createContextTab(contextLayout);
            obj.createControlTab(ctrlLayout);

            % Rotation/zoom/pan modes require container with pixels prop
            % Using Matlab's uipanel between render axes and HBoxFlex
            hp = uipanel('Parent', mainLayout,...
                'BackgroundColor', 'w');

            % Create the render axes
            obj.ax = axes('Parent', hp);
            axis(obj.ax, 'equal', 'tight');
            grid(obj.ax, 'on');
            view(obj.ax, 3);
            xlabel(obj.ax, 'X');
            ylabel(obj.ax, 'Y');
            zlabel(obj.ax, 'Z');

            % Set up the lighting
            obj.lights = [light(obj.ax), light(obj.ax)];
            lightangle(obj.lights(1), 45, 30);
            lightangle(obj.lights(2), 225, 30);

            set(mainLayout, 'Widths', [-1 -3]);
        end

        function createNeuronTab(obj)
            obj.ui.source = uicontrol(obj.ui.root,...
                'Style', 'text',...
                'String', obj.source);

            % Create the neuron table
            obj.neuronTree = uiextras.jTree.CheckboxTree(...
                'Parent', obj.ui.root,...
                'RootVisible', false,...
                'CheckboxClickedCallback', @obj.onNodeChecked);

            % Add/remove neurons
            pmLayout = uix.HBox('Parent', obj.ui.root,...
                'BackgroundColor', 'w',...
                'Spacing', 5);
            idLayout = uix.VBox('Parent', pmLayout,...
                'BackgroundColor', [1 1 1],...
                'Spacing', 5);
            uicontrol(idLayout,...
                'Style', 'text',...
                'String', 'IDs:');
            obj.ui.newID = uicontrol(idLayout,...
                'Style', 'edit',...
                'TooltipString', 'Input ID(s) separated by commas',...
                'String', '');
            buttonLayout = uix.VBox('Parent', pmLayout,...
                'BackgroundColor', 'w');
            obj.ui.add = uicontrol(buttonLayout,...
                'Style', 'push',...
                'String', '+',...
                'FontWeight', 'bold',...
                'FontSize', 20,...
                'TooltipString', 'Add neuron(s) in editbox',...
                'Callback', @obj.onAddNeuron);
            obj.ui.nextColor = uicontrol(buttonLayout,...
                'Style', 'push',...
                'String', ' ',...
                'BackgroundColor', [0.5, 0, 1],...
                'TooltipString', 'Click to change next neuron color',...
                'Callback', @obj.onSetNextColor);
            set(buttonLayout, 'Heights', [-1.2 -.8])
            set(pmLayout, 'Widths', [-1.2, -0.8])

            % Plot modifiers
            obj.ui.status = uicontrol(obj.ui.root,...
                'Style', 'text',...
                'String', ' ',...
                'FontAngle', 'italic');

            % Disable until new neuron is imported
            set(obj.ui.root, 'Heights', [-.5 -5 -1.5 -.5]);
        end

        function createContextTab(obj, contextLayout)
            if strcmp(obj.source, 'RC1')
                uicontrol(contextLayout, 'Style', 'text',...
                    'String', 'No markers or cones for RC1');
                return;
            end
            uicontrol(contextLayout,...
                'Style', 'text', 'String', 'Boundary Markers:',...
                'FontWeight', 'bold');
            uicontrol(contextLayout,...
                'Style', 'check', 'String', 'INL Boundary',...
                'Tag', 'INL',...
                'TooltipString', 'Add INL Boundary',...
                'Callback', @obj.onAddBoundary);
            uicontrol(contextLayout,...
                'Style', 'check', 'String', 'GCL Boundary',...
                'TooltipString', 'Add GCL Boundary',...
                'Tag', 'GCL',...
                'Callback', @obj.onAddBoundary);
            uicontrol(contextLayout,...
                'Style', 'check',...
                'String', '915 Gap',...
                'TooltipString', 'Add 915-936 gap',...
                'Callback', @obj.onAddGap);
            uix.Empty('Parent', contextLayout);
            if strcmp(obj.source, 'NeitzTemporalMonkey')
                uicontrol(contextLayout, 'Style', 'text',...
                    'String', 'No cones for TemporalMonkey');
            else
                uicontrol(contextLayout,...
                    'Style', 'text', 'String', 'Cone Mosaic:',...
                    'FontWeight', 'bold');
                uicontrol(contextLayout,...
                    'Style', 'check', 'String', 'S-cones',...
                    'Tag', 'addS',...
                    'Callback', @obj.onAddCones);
                uicontrol(contextLayout,...
                    'Style', 'check', 'String', 'L/M-cones',...
                    'Tag', 'addLM',...
                    'Callback', @obj.onAddCones);
                uicontrol(contextLayout,...
                    'Style', 'check', 'String', 'Unknown',...
                    'Tag', 'addU',...
                    'TooltipString', 'Add cones of unknown type',...
                    'Callback', @obj.onAddCones);
                uicontrol(contextLayout,...
                    'Style', 'check', 'String', 'Blood Vessels',...
                    'TooltipString', 'Import blood vessels',...
                    'Callback', @obj.onAddBloodVessels);
                uicontrol(contextLayout,...
                    'Style', 'text', 'String', 'Transform: ');
                uicontrol(contextLayout,...
                    'Style', 'popup',...
                    'String', {'Viking', 'Local'},...
                    'Callback', @obj.onSetTransform);
                set(contextLayout, 'Heights', [-0.5, -1, -1, -1, -1, -0.5, -1, -1, -1, -1, -0.5, -1]);
            end
        end

        function createControlTab(obj, ctrlLayout)
            uicontrol(ctrlLayout,...
                'Style', 'text', 'String', 'Display options:',...
                'FontWeight', 'bold');
            g = uix.Grid('Parent', ctrlLayout,...
                'BackgroundColor', 'w',...
                'Spacing', 5);
            uicontrol(g,...
                'Style', 'check',...
                'String', 'Invert',...
                'Callback', @obj.onToggleInvert);
            uicontrol(g,...
                'Style', 'check',...
                'String', 'Grid',...
                'Value', 1,...
                'TooltipString', 'Show/hide grid',...
                'Callback', @obj.onToggleGrid);
            uicontrol(g,...
                'Style', 'check',...
                'String', 'Axes',...
                'Value', 1,...
                'TooltipString', 'Show/hide axes',...
                'Callback', @obj.onToggleAxes);
            uicontrol(g,...
                'Style', 'check',...
                'String', '2D',...
                'TooltipString', 'Toggle b/w 3D and flat 2D',...
                'Callback', @obj.onToggleLights);

            set(g, 'Heights', [-1 -1], 'Widths', [-1, -1]);
            uicontrol(ctrlLayout,...
                'Style', 'text',...
                'String', 'Axis rotation:',...
                'Tag', 'AxTheta');
            uicontrol(ctrlLayout,...
                'Style', 'text', 'String', 'Transparency:')
            uicontrol(ctrlLayout,...
                'Style', 'popup',...
                'String', {'0.1', '0.2', '0.3', '0.4', '0.5',...
                    '0.6', '0.7', '0.8', '0.9', '1'},...
                'Value', 10,...
                'Tag', 'DefaultAlpha',...
                'Callback', @obj.onSetTransparency);
            uix.Empty('Parent', ctrlLayout);
            uicontrol(ctrlLayout,...
                'Style', 'text', 'String', 'Axis options:',...
                'FontWeight', 'bold');
            rotLayout = uix.HBox('Parent', ctrlLayout,...
                'BackgroundColor', 'w');
            rotations = {'XY1', 'XY2', 'XZ', 'YZ', '3D'};
            for i = 1:numel(rotations)
                uicontrol(rotLayout,...
                    'Style', 'push',...
                    'String', rotations{i},...
                    'Tag', rotations{i},...
                    'Callback', @obj.onSetRotation);
            end
            uicontrol(ctrlLayout,...
                'Style', 'text', 'String', 'Axis Limits');
            uitable(ctrlLayout,...
                'Data', {false, 0, 1; false, 0, 1; false, 0, 1},...
                'ColumnEditable', true,...
                'ColumnWidth', {20, 35, 35},...
                'RowName', {'X', 'Y', 'Z'},...
                'ColumnName', {'', 'Min', 'Max'},...
                'CellEditCallback', @obj.onSetLimits);
            uicontrol(ctrlLayout,...
                'Style', 'push',...
                'String', 'Add ScaleBar',...
                'Callback', @onAddScaleBar);

            set(ctrlLayout, 'Heights',...
                [-0.5, -2, -0.5, -1, -0.5, -0.5, -0.5, -1, -0.5, -2.5, -0.75]);
        end

        function createToolbar(obj)
            mh.export = uimenu(obj.figureHandle, 'Label', 'Export');
            uimenu(mh.export, 'Label', 'Open in new figure window',...
                'Callback', @obj.onExportFigure);
            uimenu(mh.export, 'Label', 'Export as image',...
                'Callback', @obj.onExportImage);
            uimenu(mh.export, 'Label', 'Export as image (high res)',...
                'Callback', @obj.onExportImage);
            uimenu(mh.export, 'Label', 'Export as COLLADA',...
                'Callback', @obj.onExportCollada);
            uimenu(mh.export, 'Label', 'Send neurons to workspace',...
                'Callback', @obj.onExportNeuron);

            mh.help = uimenu(obj.figureHandle, 'Label', 'Help');
            uimenu(mh.help, 'Label', 'Keyboard controls',...
                'Tag', 'navigation',...
                'Callback', @obj.openHelpDlg);
            uimenu(mh.help, 'Label', 'Annotation import',...
                'Tag', 'import',...
                'Callback', @obj.openHelpDlg);
            uimenu(mh.help, 'Label', 'Scalebar',...
                'Tag', 'scalebar',...
                'Callback', @obj.openHelpDlg);
        end
    end

    methods (Static = true)
        function lim = getLimits(ax)
            lim = [get(ax, 'XLim'); get(ax, 'YLim'); get(ax, 'ZLim')];
        end
        
        function setLimits(ax, lim)
            set(ax, 'XLim', lim(1,:), 'YLim', lim(2,:), 'ZLim', lim(3,:));
        end
        
        function newNode = addSynapseNode(parentNode, synapseName)
            % ADDSYNAPSENODE
            newNode = uiextras.jTree.CheckboxTreeNode(...
                'Name', char(synapseName),...
                'Parent', parentNode);
        end

        function tag = id2tag(id)
            % ID2TAG  Quick fcn for (127 -> 'c127')
            tag = sprintf('c%u', id);
        end

        function id = tag2id(tag)
            % TAG2ID  Quick fcn for ('c127' -> 127)
            id = str2double(tag(2:end));
        end

        function str = formatCoordinates(pos, ds)
            % FORMATCOORDINATES  Sets coordinates to paste into Viking
            if nargin < 2
                ds = 2;
            end
            str = sprintf('X: %.1f Y: %.1f Z: %u DS: %u',...
                pos(1), pos(2), round(pos(3)), ds);
        end

        function str = getInstructions()
            % GETINSTRUCTIONS  Return instructions as multiline string
            str = sprintf(['NAVIGATION CONTROLS:\n',...
                '\nROTATE: arrow keys\n',...
                '   Azimuth: left, right\n',...
                '   Elevation: up, down\n',...
                '\nZOOM: ''z''\n',...
                '   To switch directions, press SHIFT+Z once\n',...
                '\nPAN:\n',...
                '   X-axis: ''a'' and ''d''\n',...
                '   Y-axis: ''q'' and ''e''\n',...
                '\nRESET axis: ''m''\n',...
                '   Z-axis: ''w'' and ''s''\n',...
                '\nCOPY location to clipboard:\n'...
                '   Click on figure then press ''c''\n',...
                '\nHELP: ''h''\n']);
        end
    end
end
