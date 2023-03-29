function [chanMapFile, probe] = createChannelMapFile_KSW(savepath, metadataFile, probe)
% savepath = createChannelMapFile_KSW(savepath, metadataFile, probe)
%
% Creates Kilosort chanMap file.
%
% Function takes in the specified probe name (current preferred method) or
% a metadata file in the form of either CellExplorer session.mat file or
% Neuoscope XML file, generates Kilosort channel map (chanMap.mat) file for
% a given ecephys recording probe, and saves the file in the specified
% location.
%
% Args:
%   savepath (char): a shape-(1, M) full path string for saving the
%     chanMap.mat file. Typically, it is the folder where the raw data is
%     stored (basepath). Will use the current working directory by default
%     or if left empty.
%   metadataFile (char): a shape-(1, M) full path string containing
%     metadata file name. Preferably it should be the CellExplorer
%     generated session.mat file or, else, an XML file generated by the
%     Neuroscope. Will use continuous.session.mat name by default
%     or if left empty. If continuous.session.mat does not exist, will
%     also check for continuous.xml file. If probe name is specified, then
%     probe metadata loading from a file will be overriden by the wrapper
%     and the locally available info in the chanMaps folder will be used
%     instead.
%   probe (char): a shape-(1, M) string with the name of the probe. By
%     default or if left empty, will attempt to load the probe
%     configuration from the metadata file. If the metadata file has no
%     probe configuration information, the function will assume that you
%     are using Neuropixels1_checkerboard probe. If the probe name is
%     specified, the function will override any defaults and will ignore
%     any information available in the metadata file. It will use a
%     corresponding probe channel map object file located inside the
%     chanMaps folder. Currently supported probes are:
%       Neuropixels1_checkerboard
%       Add more probe designs later
%
% Returns:
%   chanMapFile (char): a shape-(1, M) full path string with the full path
%     name of the newly generated channel map file.
%   probe (char): a shape-(1, M) string with the name of the probe for
%     which the channel map file has been produced.
%
% Comments:
%   Witten by Martynas Dervinis (martynas.dervinis@gmail.com) at Petersen
%   Lab, University of Copenhagen.

arguments
  savepath (1,:) char = pwd
  metadataFile (1,:) char = ''
  probe (1,:) char {ismember(probe, {'Neuropixels1_checkerboard',''})} = ''
end
supportedProbesFromMetadata = {'staggered','neurogrid','grid','poly3','poly5','twohundred'};


%% Parse input
if isempty(savepath)
  savepath = pwd;
end

if isempty(probe)
  loadMetadata = true;
  if ~isempty(metadataFile)
    if ~exist(metadataFile, 'file')
      error('The supplied metadata file does not exist and the probe name not specified: Unable to infer probe metadata.')
    elseif ~strcmpi(metadataFile(end-2:end), 'mat') && ~strcmpi(metadataFile(end-2:end), 'xml')
      error('Unsupported metadata file format. Only MAT and XML formats are supported.')
    end
  else
    if exists('continuous.session.mat', 'file')
      metadataFile = fullfile(savepath, 'continuous.session.mat');
    elseif exists('continuous.xml', 'file')
      metadataFile = fullfile(savepath, 'continuous.xml');
    else
      loadMetadata = false;
      probe = 'Neuropixels1_checkerboard';
    end
  end
else
  loadMetadata = false;
end


%% Parse metadata
if loadMetadata % Legacy mode
  disp('Loading probe metadata');
  if strcmpi(metadataFile(end-2:end), 'mat') % MAT format compatible with CellExplorer
    load(metadataFile); %#ok<*LOAD> 
    if ~exist('session', 'var') % Reserved variable
      error('Supplied MAT metadata file is missing session info!')
    elseif ~isfield(session, 'extracellular')
      error('Supplied MAT metadata file is missing session.extracellular field!')
    elseif ~isfield(session.extracellular, 'equipment')
      error('Supplied MAT metadata file is missing session.extracellular.equipment field!')
    end
    probe = session.extracellular.equipment;
    electrodeGroups = session.extracellular.electrodeGroups.channels; % Anatomical electrode groups. Could be grouped based on shank, brain area, or both.
    params = [];
  elseif strcmpi(metadataFile(end-2:end), 'xml') % XML format compatible with Neuroscope
    [params, rxml] = LoadXml(metadataFile);
    probe = rxml.child(1).child(4).value;
    nElectrodeGroups = numel(params.AnatGrps);
    for g = 1:nElectrodeGroups
      electrodeGroups{g} = params.AnatGrps(g).Channels;
    end
  end
  if ~ismember(probe, supportedProbesFromMetadata) % The wrapper can only load specific probes listed in supportedProbesFromMetadata
    errMsg = ['Unsupported probe type loaded from the metadata file: ' probe '. The following probes are supported: '];
    for iProbe = 1:numel(supportedProbesFromMetadata)
      if iProbe < numel(supportedProbesFromMetadata)
        errMsg = [errMsg supportedProbesFromMetadata{iProbe} ', ']; %#ok<*AGROW> 
      else
        errMsg = [errMsg 'and ' supportedProbesFromMetadata{iProbe} '.'];
      end
    end
    error(errMsg)
  end
else % Currently preferred mode
  disp('Infering probe metadata');
end


%% Construct the probe channel map
disp('Constructing the probe channel map')
if loadMetadata
  [chanMap, chanMap0ind, connected, xcoords, ycoords, kcoords] = mapFromMetadata(probe, electrodeGroups, params); % Legacy method
else
  [chanMap, chanMap0ind, connected, xcoords, ycoords, kcoords] = mapFromLocal(probe); % The new method
end


%% Save the channel map file for Kilosort
disp('Saving the probe channel map file')
chanMapFile = fullfile(savepath,'chanMap.mat');
save(chanMapFile, 'chanMap','chanMap0ind','connected','xcoords','ycoords','kcoords', '-v7.3');




%% Local functions
function [chanMap, chanMap0ind, connected, xcoords, ycoords, kcoords] = mapFromMetadata(probe, groups, par)
% [chanMap, chanMap0ind, connected, xcoords, ycoords, kcoords] = mapFromMetadata(probe, groups, par)
%
% Constructs the probe channel map from metadata.
%
% This is the legacy code inherited from the old createChannelMapFile_KSW
% KilosortWrapper subfunction. Original function was written by Brendon and
% Sam.

xcoords = [];%eventual output arrays
ycoords = [];

ngroups = numel(groups);

switch(probe)
    case 'staggered'
        for a= 1:ngroups %being super lazy and making this map with loops
            x = [];
            y = [];
            tchannels  = groups{a};
            for i =1:length(tchannels)
                x(i) = 20;%length(tchannels)-i;
                y(i) = -i*20;
                if mod(i,2)
                    x(i) = -x(i);
                end
            end
            x = x+a*200;
            xcoords = cat(1,xcoords,x(:));
            ycoords = cat(1,ycoords,y(:));
        end
    case 'poly3'
        disp('poly3 probe layout')
        for a= 1:ngroups %being super lazy and making this map with loops
            tchannels  = groups{a};
            x = nan(1,length(tchannels));
            y = nan(1,length(tchannels));
            extrachannels = mod(length(tchannels),3);
            polyline = mod([1:length(tchannels)-extrachannels],3); %#ok<*NBRAK2> 
            x(find(polyline==1)+extrachannels) = -18;
            x(find(polyline==2)+extrachannels) = 0;
            x(find(polyline==0)+extrachannels) = 18;
            x(1:extrachannels) = 0;
            y(find(x == 18)) = [1:length(find(x == 18))]*-20; %#ok<*NBRAK1> 
            y(find(x == 0)) = [1:length(find(x == 0))]*-20-10+extrachannels*20;
            y(find(x == -18)) = [1:length(find(x == -18))]*-20;
            x = x+a*200;
            xcoords = cat(1,xcoords,x(:));
            ycoords = cat(1,ycoords,y(:));
        end
    case 'poly5'
        disp('poly5 probe layout')
        for a= 1:ngroups %being super lazy and making this map with loops
            tchannels  = groups{a};
            x = nan(1,length(tchannels));
            y = nan(1,length(tchannels));
            extrachannels = mod(length(tchannels),5);
            polyline = mod([1:length(tchannels)-extrachannels],5);
            x(find(polyline==1)+extrachannels) = -2*18;
            x(find(polyline==2)+extrachannels) = -18;
            x(find(polyline==3)+extrachannels) = 0;
            x(find(polyline==4)+extrachannels) = 18;
            x(find(polyline==0)+extrachannels) = 2*18;
            x(1:extrachannels) = 18*(-1).^[1:extrachannels];
            
            y(find(x == 2*18)) =  [1:length(find(x == 2*18))]*-28;
            y(find(x == 18)) =    [1:length(find(x == 18))]*-28-14;
            y(find(x == 0)) =     [1:length(find(x == 0))]*-28;
            y(find(x == -18)) =   [1:length(find(x == -18))]*-28-14;
            y(find(x == 2*-18)) = [1:length(find(x == 2*-18))]*-28;
            
            x = x+a*200;
            xcoords = cat(1,xcoords,x(:));
            ycoords = cat(1,ycoords,y(:));
        end
    case 'neurogrid'
        for a= 1:ngroups %being super lazy and making this map with loops
            x = [];
            y = [];
            tchannels  = groups{a};
            for i =1:length(tchannels)
                x(i) = length(tchannels)-i;
                y(i) = -i*50;
            end
            x = x+a*50;
            xcoords = cat(1,xcoords,x(:));
            ycoords = cat(1,ycoords,y(:));
        end
    case 'twohundred'
        for a= 1:ngroups 
            x = [];
            y = [];
            tchannels  = groups{a};
            for i =1:length(tchannels)
                x(i) = 0;%length(tchannels)-i;
                if mod(i,2)
                    y(i) = 0;%odds
                else
                    y(i) = 200;%evens
                end
            end
            x = x+(a-1)*200;
            xcoords = cat(1,xcoords,x(:));
            ycoords = cat(1,ycoords,y(:));
        end
end
Nchannels = length(xcoords);

kcoords = zeros(1,Nchannels);
switch(probe)
    case 'neurogrid'
        for a= 1:ngroups
            kcoords(groups{a}+1) = floor((a-1)/4)+1;
        end
    otherwise
        for a= 1:ngroups
            kcoords(groups{a}+1) = a;
        end
end
connected = true(Nchannels, 1);

% just use AnatGrps
% % Removing dead channels by the skip parameter in the xml
% % order = [par.AnatGrps.Channels];
% % skip = find([par.AnatGrps.Skip]);
% % connected(order(skip)+1) = false;
if ~isempty(par) % modified by MD
  order = [par.AnatGrps.Channels];
  if isfield(par,'SpkGrps')
    skip2 = find(~ismember([par.AnatGrps.Channels], [par.SpkGrps.Channels])); % finds the indices of the channels that are not part of SpkGrps
    connected(order(skip2)+1) = false; %#ok<*FNDSB> 
  end
end

chanMap     = 1:Nchannels;
chanMap0ind = chanMap - 1;
[~,I] =  sort(horzcat(groups{:}));
xcoords = xcoords(I)';
ycoords  = ycoords(I)';


function [chanMap, chanMap0ind, connected, xcoords, ycoords, kcoords] = mapFromLocal(probe)

if strcmpi(probe, 'Neuropixels1_checkerboard')
  probeObj = Neuropixels1_checkerboard_probeMap;
  chanMap = probeObj.get_ks_map;
end

chanMap0ind = chanMap.chanMap0ind;
connected = chanMap.connected;
xcoords = chanMap.xcoords;
ycoords = chanMap.ycoords;
kcoords = chanMap.kcoords;
chanMap = chanMap.chanMap;