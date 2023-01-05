clc;
clear all;
list = blelist
devN = str2num(input("Device number from ble list ",'s'));
deviceName = list.Name(devN);
if isempty(deviceName)
    return
end
h10 = PolarH10(deviceName,'accSampleRate',100,'accRange',8);
