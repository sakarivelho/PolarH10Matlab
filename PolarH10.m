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
            uicontrol('Parent',h,'Style','pushbutton','String','Stream','Units','normalized','Position',[0.0 0.5 0.1 0.1],'Visible','on','BackgroundColor','w','Callback', {@obj.startDataStream});
            uicontrol('Parent',h,'Style','pushbutton','String','Stop','Units','normalized','Position',[0.92 0.5 0.08 0.1],'Visible','on','BackgroundColor','w','Callback', {@obj.stopDataStream});
            uicontrol('Parent',h,'Style','pushbutton','String','Exit','Units','normalized','Position',[0 0 0.1 0.1],'Visible','on','BackgroundColor','w','Callback', {@obj.exit});
            uicontrol('Parent',h,'Style','pushbutton','String','Save','Units','normalized','Position',[0 0.9 0.1 0.1],'Visible','on','BackgroundColor','w','Callback', {@obj.saveData});
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
                inDataHex = dec2hex(data);
                obj.displayIncomingWriteMessage(inDataHex);                
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
            samples = (length(data)-10)/3;
            timestamps = double(typecast(swapbytes(data(2:9)),'uint64'));
            timestamps = timestamps/(10^9);
            for i = 0:samples-1
                position = 11 + i*3;
                % %             int24 to int32 conversion
                sample = uint8([0 data(position:position+2)]);
                ecg = typecast(swapbytes(sample),'int32');
                ecgOut = double(bitshift(ecg,-8,'int32'));
                obj.ecgData = [obj.ecgData, ecgOut];
                obj.ecgTimeStamps = [obj.ecgTimeStamps timestamps];
            end
            obj.plotData();
        end
        
        function readPolarAccData(obj,data)
            %             Byte 1   for datatime
            %             Bytes 2:9  for timestamps
            %             Byte 10 for frame
            %             Bytes 11:end  for acc data(x,y,z) as int16
            dataLen = length(data);
            timestamps = double(typecast(swapbytes(data(2:9)),'uint64'));
            timestamps = timestamps/(10^9);
            samples = (dataLen-10)/6;
            for i = 0:samples-1
                position = 11 + i*6;
                [accX, accY,accZ] = obj.read16BitValues(data(position:position+5));
                %                 Values in milliG's -> divide by 1000
                obj.accXData = [obj.accXData, accX/1000];
                obj.accYData = [obj.accYData, accY/1000];
                obj.accZData = [obj.accZData, accZ/1000];
                obj.accTimeStamps = [obj.accTimeStamps timestamps];
            end
            %             obj.plotData();
        end
        
        
        function [x,y,z] = read16BitValues(~,data)
            x = double(typecast(swapbytes(data(1:2)),'int16'));
            y = double(typecast(swapbytes(data(3:4)),'int16'));
            z = double(typecast(swapbytes(data(5:6)),'int16'));
            
        end
        
        function plotData(obj)
            obj.plotHandleX.YData = [obj.accXData];
            obj.plotHandleY.YData = [obj.accYData];
            obj.plotHandleZ.YData = [obj.accZData];
            obj.plotHandleEcg.YData = [obj.ecgData];
            obj.plotHandleEcg.Parent.XLim = [length(obj.plotHandleEcg.YData)-obj.plotLength*obj.accSampleRate, length(obj.plotHandleEcg.YData)];
            obj.plotHandleX.Parent.XLim = [length(obj.plotHandleX.YData)-obj.plotLength*obj.ecgSampleRate, length(obj.plotHandleX.YData)];
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
        
        function displayIncomingWriteMessage(obj,hexMsg)
            if ~strcmp(hexMsg(1,:),'F0')
                disp("Received unknown message")
                return
            end
            outMsg = "Polar H10 command: ";
            switch string(hexMsg(2,:))
                case "02"
                    outMsg = outMsg + "start ";
                case "03"
                    outMsg = outMsg + "stop ";
                case "01"
                    outMsg = " measurement settings query. Response :";
                    for i = 1:height(hexMsg)
                        outMsg = outMsg + " "+ string(hexMsg(i,:));
                    end
                    disp(outMsg);
                    return
                otherwise
                    return
            end
            switch string(hexMsg(3,:))
                case "00"
                    outMsg = outMsg + "ECG measurement.";
                case "02"
                    outMsg = outMsg + "ACC measurement.";
                otherwise
            end
            switch string(hexMsg(4,:))
                case "00"
                    outMsg = outMsg + " Status: Success";
                otherwise
                    outMsg = sprintf("%s Status: Error (code %s)",outMsg,string(hexMsg(4,:)));
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


