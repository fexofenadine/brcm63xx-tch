#!/bin/sh
echo 0 > /sys/class/leds/broadband\:green/brightness
echo 0 > /sys/class/leds/ethernet:green/brightness
echo 0 > /sys/class/leds/internet:green/brightness
echo 0 > /sys/class/leds/iptv:green/brightness
echo 0 > /sys/class/leds/power:green/brightness
echo 0 > /sys/class/leds/voip:green/brightness
echo 0 > /sys/class/leds/wireless:green/brightness
echo 0 > /sys/class/leds/wireless_5g:green/brightness
echo 0 > /sys/class/leds/wps:green/brightness 
echo 1 > /sys/class/leds/power:blue/brightness
