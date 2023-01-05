clc
clear all
[f,p] = uigetfile('*.mat');
fName = fullfile(p,f);
load(fName);
%% 

% [accTime,missingAccPackets] = interpolatePolarTimestamps(results.accTimeStamps,results.accSampleRate);
% [ecgTime,missingEcgPackets] = interpolatePolarTimestamps(results.ecgTimeStamps,results.ecgSampleRate);
% fprintf("Missing %i acc packets \nMissing %i ecg packets\n",missingAccPackets,missingEcgPackets);


%% Plot data
j = figure;
ax1 = subplot(2,1,1);
plot(results.ecgTimestamps,results.ecgData,'DisplayName','Ecg');
ylabel(results.ecgUnits);
ylim([-2500,2500]);
ax2 = subplot(2,1,2);
plot(results.accTimestamps,results.accXData,'-r','DisplayName','X');
hold on
plot(results.accTimestamps,results.accYData,'-g','DisplayName','Y');
plot(results.accTimestamps,results.accZData,'-b','DisplayName','Z');
ylabel(results.accUnits);
legend
hold off
linkaxes([ax1 ax2], 'x')
xlim([min([results.accTimestamps results.ecgTimestamps]),max([results.accTimestamps results.ecgTimestamps])]);
j.WindowState = 'maximize';

