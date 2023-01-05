classdef PolarH10 < handle
    % % Object to capture PolarH10 ecg & acc data
    % % Polar measurement data specification:
    % % https://github.com/polarofficial/polar-ble-sdk/blob/master/technical_documentation/Polar_Measurement_Data_Specification.pdf
    properties (Access = private)
        serviceUUID = "FB005C80-02E7-F387-1CAD-8ACD2D8DF0C8";
        writeCharacteristic = "FB005C81-02E7-F387-1CAD-8ACD2D8DF0C8";
        notifyCharacteristic = "FB005C82-02E7-F387-1CAD-8ACD2D8DF0C8";
        figure;
        connection;
        write;
        notify;
        plotHandleX;
        plotHandleY;
        plotHandleZ;
        plotHandleEcg;
        plotLength = 5;
        accSampleRate = 100;
        accRange = 8;
        ecgSampleRate = 130;
        hrChar;
        displayHr;
    end
    
    properties 
        accXData = [];
        accYData = [];
        accZData = [];
        ecgData = [];
        accTimeStamps = [];
        ecgTimeStamps = [];
    end
    
    methods
        function obj = PolarH10(name,options)
            arguments
                name string
                options.accSampleRate double {mustBeMember(options.accSampleRate,[25,50,100,200])} = 100
                options.accRange double {mustBeMember(options.accRange,[2,4,8])} = 8
                options.displayHr logical = false;
            end
            obj.accSampleRate = options.accSampleRate;
            obj.accRange = options.accRange;
            obj.displayHr = options.displayHr;
                
            obj.connection = ble(name);
            h = figure('Name',name);
            set(h,'color','w');
            obj.figure =h;
            uicontrol('Parent',h,'Style','pushbutton','String','Stream',...
                'Units','normalized','Position',[0.0 0.5 0.1 0.1],'Visible','on','BackgroundColor','w','Callback', {@obj.startDataStream});
            uicontrol('Parent',h,'Style','pushbutton','String','Stop',...
                'Units','normalized','Position',[0.92 0.5 0.08 0.1],'Visible','on','BackgroundColor','w','Callback', {@obj.stopDataStream});
            uicontrol('Parent',h,'Style','pushbutton','String','Exit',...
                'Units','normalized','Position',[0 0 0.1 0.1],'Visible','on','BackgroundColor','w','Callback', {@obj.exit});
            uicontrol('Parent',h,'Style','pushbutton','String','Save',...
                'Units','normalized','Position',[0 0.9 0.1 0.1],'Visible','on','BackgroundColor','w','Callback', {@obj.saveData});
            subplot(2,1,1)
            plotHandleX = plot([0],'-');
            title("Acc");
            ylim([-obj.accRange,obj.accRange]);
            set(gca,'xticklabel',[])
            hold on;
            plotHandleY = plot([0],'-');
            plotHandleZ = plot([0],'-');
            subplot(2,1,2)
            plothandleEcg = plot([1],'-');
            title("Ecg");
            ylim([-2500,2500]);
            set(gca,'xticklabel',[])
            obj.write = characteristic(obj.connection,obj.serviceUUID,obj.writeCharacteristic);
            obj.write.DataAvailableFcn = @displayWriteData;
            obj.notify = characteristic(obj.connection,obj.serviceUUID,obj.notifyCharacteristic);
            obj.notify.DataAvailableFcn  = @displayCharcteristicData;
            
            if obj.displayHr
                obj.hrChar = characteristic(obj.connection, "heart rate", "heart rate measurement");
                obj.hrChar.DataAvailableFcn = @displayHrData;
            end
            obj.plotHandleX = plotHandleX;
            obj.plotHandleY = plotHandleY;
            obj.plotHandleZ = plotHandleZ;          
            obj.plotHandleEcg = plothandleEcg;
            function displayCharcteristicData(src,~)
                data = read(src,'oldest');
                obj.handleIncomingData(data);
            end
            
            function displayWriteData(src,~)
                data = read(src,'oldest');
                obj.displayIncomingWriteMessage(data);                
            end
            
            function displayHrData(src,~)
                data = read(src,'oldest');
                flag = uint8(data(1));
                % Get the first bit of the flag, which indicates the format of the heart rate value
                heartRateValueFormat = bitget(flag, 1);
                if heartRateValueFormat == 0
                    % Heart rate format is uint8
                    heartRate = data(2);
                else
                    % Heart rate format is uint16
                    heartRate = double(typecast(uint8(data(2:3)), 'uint16'));
                end
               fprintf('Heart rate measurement: %d(bpm)\n', heartRate);
            end
           
        end
    end
    methods (Access=private)
        
        function handleIncomingData(obj,data)
            u8Data = uint8(data);
            type = data(1);
            switch type
                case 2
                    obj.readPolarAccData(u8Data)
                case 0
                    obj.readPolarEcgData(u8Data);
                otherwise
                    disp("Selected dataformat not supported")
            end
            
        end
        
        function startDataStream(obj,~,~)
            obj.clearData();
            accSubMsg = uint8([2 2 2 1 obj.accRange 0 0 1 obj.accSampleRate 0 1 1 16 0]);
            ecgSubMsg = uint8([2 0 0 1 130 0 1 1 14 0]);
            write(obj.write,ecgSubMsg);
            pause(0.5);
            write(obj.write,accSubMsg);
        end
        
        function readPolarEcgData(obj,data)
            tempEcg = [];
            samples = (length(data)-10)/3;
            timestamp = double(typecast(swapbytes(data(2:9)),'uint64'));
            timestamp = timestamp/(10^9);
            % Convert int24 array to int32 array:
            % Reshape to one row per sample and pad with zeros
            ecgInt24Data = data(11:end);
            shaped = reshape(ecgInt24Data,3,[])';
            padded = [zeros(height(shaped),1),shaped];
            % reshape back to column vector, cast to int32 and bitshift all values -8
            ecgData = bitshift(typecast(reshape(padded',1,[]),'int32'),-8,'int32');
            timestamps = ones(1,length(ecgData))*timestamp;           
            obj.ecgData = [obj.ecgData,ecgData];
            obj.ecgTimeStamps = [obj.ecgTimeStamps,timestamps];
            obj.plotData();
        end
        
        function readPolarAccData(obj,data)
            %             Bytes 2:9  for timestamps
            %             Bytes 11:end  for acc data(x,y,z) as int16
            timestamp = double(typecast(swapbytes(data(2:9)),'uint64'));
            timestamp = timestamp/(10^9);
%             Convert to int16
            acc8 = data(11:end);
%           Cast to int16,convert to double and divide by 1000 to get
%           millisG's to G's
            acc = double(typecast(acc8,'int16'))/1000;
            x = acc(1:3:end);
            y = acc(2:3:end);
            z = acc(3:3:end);
            obj.accXData = [obj.accXData, x];
            obj.accYData = [obj.accYData, y];
            obj.accZData = [obj.accZData, z];
            timestamps = ones(1,length(x))*timestamp;
            obj.accTimeStamps = [obj.accTimeStamps timestamps];
        end
        
   
        
        function plotData(obj)
            obj.plotHandleX.YData = [obj.accXData];
            obj.plotHandleY.YData = [obj.accYData];
            obj.plotHandleZ.YData = [obj.accZData];
            obj.plotHandleEcg.YData = [obj.ecgData];
            obj.plotHandleEcg.Parent.XLim = [length(obj.plotHandleEcg.YData)-obj.plotLength*obj.ecgSampleRate, length(obj.plotHandleEcg.YData)];
            obj.plotHandleX.Parent.XLim = [length(obj.plotHandleX.YData)-obj.plotLength*obj.accSampleRate, length(obj.plotHandleX.YData)];
        end
        
        
        function stopDataStream(obj,~,~)
            %             Unsub acceleration
            write(obj.write, uint8([3 0]));
            pause(0.3);
            %             Unsub ecg
            write(obj.write, uint8([3 2]));
        end
        
        function exit(obj,~,~)
            delete(obj.figure)
            obj.connection ="";
            clear obj.connection;
        end
        
        function saveData(obj,~,~)
            results = struct();
            [accTime,missingAccPackets] = obj.interpolatePolarTimestamps(obj.accTimeStamps,obj.accSampleRate);
            [ecgTime,missingEcgPackets] = obj.interpolatePolarTimestamps(obj.ecgTimeStamps,obj.ecgSampleRate);
            if (missingAccPackets + missingEcgPackets) > 0
                fprintf("Missing data in Polar data: %i acc packets , %i ecg packets.\n Check saved data!",missingAccPackets,missingEcgPackets);
            end
            results.accUnits = 'g';
            results.accSampleRate = obj.accSampleRate;
            results.accPacketTimestamps = obj.accTimeStamps;
            results.accTimestamps = accTime;
            results.accXData = obj.accXData;
            results.accYData = obj.accYData;
            results.accZData = obj.accZData;
            results.ecgUnits = 'uV';
            results.ecgSampleRate = obj.ecgSampleRate;
            results.ecgPacketTimestamps = obj.ecgTimeStamps;
            results.ecgTimestamps = ecgTime;
            results.ecgData = obj.ecgData;
            [f,p] = uiputfile({'*.mat'});
            filename = fullfile(p,f);
            save(filename,'results');
            disp("Polar H10 data saved as: " + filename);
            
        end
        
        function obj = clearData(obj)
            obj.accXData = [];
            obj.accYData = [];
            obj.accZData = [];
            obj.accTimeStamps = [];
            obj.ecgData = [];
            obj.ecgTimeStamps = [];
        end
        
        function displayIncomingWriteMessage(obj,data)
          
            if data(1) ~= 240
                return
            end
            
            outMsg = string(datetime('now','Format',"HH:mm:ss")) + " Polar H10 command: ";
            switch data(2)
                case 2
                    outMsg = outMsg + "start ";
                case 3
                    outMsg = outMsg + "stop ";
                case 1
                    outMsg = " measurement settings query. Response :";
                    for i = 1:height(data)
                        outMsg = outMsg + " "+ string(dec2hex(data(i,:)));
                    end
                    disp(outMsg);
                    return
                otherwise
                    return
            end
            switch data(3)
                case 0
                    outMsg = outMsg + "ECG measurement.";
                case 2
                    outMsg = outMsg + "ACC measurement.";
                otherwise
            end
            switch data(4)
                case 0
                    outMsg = outMsg + " Status: Success";
                otherwise
                    outMsg = sprintf("%s Status: Error (code %i)",outMsg,data(4));
            end
            disp(outMsg);
        end
        
    end
    
    methods (Static = true)
        function [interpolatedStamps,nOfMissingPackets] = interpolatePolarTimestamps(timestamps,sampleRate)
            nonZero = find(diff(timestamps) ~= 0);
            % % Check validity
            packetDiff = diff(diff(nonZero));
            isValid = ~any(packetDiff ~=0);
            if ~isValid
                disp("Polar H10 packet sizes do not match. Check the data")
            end
            estimatedPacketTimeDiff = nonZero(1)*(1/sampleRate);
            nOfMissingPackets = sum(abs(diff(timestamps(nonZero))-estimatedPacketTimeDiff)>0.01);
            dt = 1/sampleRate;
            interpolatedStamps = [];
            for i = 1:length(nonZero)+1
                if i > length(nonZero)
                    stopInd = length(timestamps);
                else
                    stopInd = nonZero(i);
                end
                if i == 1
                    startInd =1;
                else
                    startInd = nonZero(i-1)+1;
                end
                stampPacket = timestamps(startInd:stopInd);
                for j = 1:length(stampPacket)
                    minus = length(stampPacket) - j;
                    stampPacket(j) = stampPacket(j) - minus*dt;
                end
                interpolatedStamps =[interpolatedStamps stampPacket];
            end
            
        end
    end
end


