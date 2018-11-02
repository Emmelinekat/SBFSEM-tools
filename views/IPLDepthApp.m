classdef IPLDepthApp < handle
    
    properties (Constant = true, Hidden = true)
        TRANSFORM = sbfsem.core.Transforms.Viking;
        SOURCES = {'NeitzTemporalMonkey','NeitzInferiorMonkey','MarcRC1'};
    end
    
    properties (SetAccess = private)
        source
        volumeScale         % Converted to microns
        iplPercent
        INL
        GCL
        fh
        axHandle
        iplMark
    end

    methods
        function obj = IPLDepthApp(source)
            if nargin == 0
                [selection, selectedSource] = listdlg(...
                    'PromptString', 'Select a source:',...
                    'Name', 'GraphApp Source Selection',...
                    'SelectionMode', 'single',...
                    'ListString', obj.SOURCES);
                if selectedSource
                    obj.source = obj.SOURCES{selection};
                    fprintf('Running with %s\n', obj.source);
                else
                    warning('No source selected... exiting');
                    return;
                end
            else
                obj.source = validateSource(source);
            end
            
            obj.getData();            
            obj.createUI();
        end
    end
    
    methods (Access = private)        
        function getData(obj)
            obj.volumeScale = getODataScale(obj.source)./1e3;
            
            obj.GCL = sbfsem.builtin.GCLBoundary(obj.source, true);
            obj.INL = sbfsem.builtin.INLBoundary(obj.source, true);
        end
        
        function createUI(obj)
            obj.fh = figure('Name', 'IPLDepthApp',...
                'DefaultUicontrolBackgroundColor', 'w',...
                'DefaultUicontrolFontSize', 10,...
                'DefaultUicontrolFontName', 'Segoe UI',...
                'NumberTitle', 'off',...
                'Menubar', 'none',...
                'Toolbar', 'none',...
                'Color', 'w');
            figPos(obj.fh, 0.4, 0.5);
            mainLayout = uix.VBox('Parent', obj.fh,...
                'BackgroundColor', 'w', 'Spacing', 10);
            
            uicontrol(mainLayout,...
                'Style', 'text', 'String', obj.source,...
                'FontWeight', 'bold');
            uicontrol(mainLayout,...
                'Style', 'text', 'String', 'Enter a location ID:');
            idLayout = uix.HBox('Parent', mainLayout,...
                'BackgroundColor', 'w');
            uicontrol(idLayout,...
                'Style', 'edit', 'Tag', 'ID');
            uicontrol(idLayout,...
                'Style', 'push', 'String', 'Go',...
                'Callback', @obj.onCalculateDepth);
            dataLayout = uix.HBox('Parent', mainLayout,...
                'BackgroundColor', 'w');
            
            obj.axHandle = axes(dataLayout,...
                'YTick', [0, 25, 50, 75, 100],...
                'YTickLabel', {'INL', 'on', '', 'off', 'GCL'},...
                'XColor', 'w',...
                'Tag', 'Graph');
            hold(obj.axHandle, 'on');
            
            ylim(obj.axHandle, [-25, 125]);
            xlim(obj.axHandle, [0.8, 1.2]);
            ylabel(obj.axHandle, 'IPL Depth');
            grid(obj.axHandle, 'on');
            
            uicontrol(dataLayout,...
                'Style', 'text', 'Tag', 'Output',...
                'HorizontalAlignment', 'center',...
                'FontSize', 20,...
                'FontWeight', 'bold');
            
            set(dataLayout, 'Widths', [-1, -1.5]);
            set(mainLayout, 'heights', [-0.8, -0.8, -1.5, -2.5])
        end
        
        function setOutput(obj, str, errorMode)
            if nargin < 3
                errorMode = false;
            end
            set(findobj(obj.fh, 'Tag', 'Output'), 'String', str);
            if errorMode
                set(findobj(obj.fh, 'Tag', 'Output'),...
                    'FontWeight', 'normal',...
                    'FontSize', 10,...
                    'ForegroundColor', 'r');
            else
                set(findobj(obj.fh, 'Tag', 'Output'),...
                    'FontWeight', 'bold',...
                    'FontSize', 20,...
                    'ForegroundColor', 'k');
            end
        end
        
        function onCalculateDepth(obj, ~, ~)
            try
                ID = get(findobj(obj.fh, 'Tag', 'ID'), 'String');
            catch
                obj.setOutput('Invalid Location ID!', true);
                return;
            end
            obj.setOutput('Querying...');
            
            try
                url = [getServiceRoot(obj.source), 'Locations(', ID, ')'];
                data = readOData(url);
            catch
                obj.setOutput('Location ID not found!', true);
                return;
            end
            
            XYZ = [data.VolumeX, data.VolumeY, data.Z];
            XYZ = XYZ .* obj.volumeScale;
            
            [X, Y] = meshgrid(obj.GCL.newXPts, obj.GCL.newYPts);
            vGCL = interp2(X, Y, obj.GCL.interpolatedSurface,...
                XYZ(1), XYZ(2));
            
            [X, Y] = meshgrid(obj.INL.newXPts, obj.INL.newYPts);
            vINL = interp2(X, Y, obj.INL.interpolatedSurface,...
                XYZ(1), XYZ(2));
            
            obj.iplPercent = (1-(XYZ(3) - vGCL)/((vINL - vGCL)+eps)) * 100;
            obj.setOutput(sprintf('%u%%', round(obj.iplPercent)));
            if isempty(obj.iplMark)                
                obj.iplMark = plot(obj.axHandle, 1, obj.iplPercent,...
                    'Marker', 'p',...
                    'Color', hex2rgb('ff4040'), 'LineStyle', 'none');
            else
                set(obj.iplMark, 'YData', obj.iplPercent);
            end
            ylim(obj.axHandle, [-25, 125]);
            xlim(obj.axHandle, [0.8, 1.2]);
            %fprintf('XYZ = %.2g, vINL = %.2g, vGCL = %.2g\n', XYZ(3), vINL, vGCL);
        end        
        
        
    end
end