#!/bin/bash
set -eo pipefail

#####
#
#  File: processautolock.sh
#
#  Copyright 2020 Michael Ortenstein
#
#  This file is part of openWB.
#
#     openWB is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
#
#     openWB is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with openWB.  If not, see <https://www.gnu.org/licenses/>.
#
#####

cd /var/www/html/openWB/
# read config file
. openwb.conf

# sets variables necessary due to inconsistent naming
powerLp1=$(<ramdisk/llaktuell)
powerLp2=$(<ramdisk/llaktuells1)
powerLp3=$(<ramdisk/llaktuells2)
powerLp4=$(<ramdisk/llaktuelllp4)
powerLp5=$(<ramdisk/llaktuelllp5)
powerLp6=$(<ramdisk/llaktuelllp6)
powerLp7=$(<ramdisk/llaktuelllp7)
powerLp8=$(<ramdisk/llaktuelllp8)

# some stuff
time=$(date +%H:%M)
dayOfWeek=$(date +%u)  # 1 = Montag

function checkDisableLp {
    powerVarName="powerLp${chargePoint}"
    now=$(date +'%Y-%m-%d %H:%M:%S');
    if [ "${!powerVarName}" -lt "200" ]; then
        # charge point stopped charging ... less than 200 W
        # delete possible wait-to-lock-flag
        echo "0" > $flagFilename
        # and disable charge point
        mqttTopic="openWB/set/lp$chargePoint/ChargePointEnabled"
        mosquitto_pub -r -t $mqttTopic -m 0
        echo "${now} auto-disabled charge point #${chargePoint}"
    else
        echo "${now} no auto-disable charge point #${chargePoint}, still charging: ${!powerVarName} W"
    fi
}

for chargePoint in {1..8}
do
    lpFilename="/var/www/html/openWB/ramdisk/lp${chargePoint}enabled"  # name of variable for lpenable
    flagFilename="/var/www/html/openWB/ramdisk/waitautolocklp${chargePoint}"  # name of variable for lp wait-to-lock
    unlocktimeSettingName="unlockTimeLp${chargePoint}_${dayOfWeek}"  # name variable of unlock time for today
    locktimeSettingName="lockTimeLp${chargePoint}_${dayOfWeek}"  # name of variable of lock time for today
    waitUntilFinishedName="waitUntilFinishedBoxLp${chargePoint}"  # name variable of checkbox value

    if [ -z "${!unlocktimeSettingName}" ]; then
        # variable is not defined in settings (or empty)
        unlockTime=""  # so set the unlock time to empty string
    else
        unlockTime="${!unlocktimeSettingName}"  # get the unlock time from setting
    fi

    if [ -z "${!locktimeSettingName}" ]; then
        # variable is not defined in settings (or empty)
        lockTime=""  # so set the lock time to empty string
    else
        lockTime="${!locktimeSettingName}"  # get the lock time from setting
    fi

    if [ -z "${!waitUntilFinishedName}" ]; then
        # variable is not defined in settings (or empty)
        waitUntilFinished="off"  # so set the value to 'dont wait'
    else
        waitUntilFinished="${!waitUntilFinishedName}"  # get the checkbox-value from setting
    fi

    # now process the settings...
    lpenabled=$(<$lpFilename)  # read ramdisk value for lp enabled
    now=$(date +'%Y-%m-%d %H:%M:%S');
    if [ "$lpenabled" = "1" ]; then
        # if the charge point is enabled, check for auto disabling
        waitFlag=$(<$flagFilename)  # read ramdisk value for lp autolock wait flag
        if [ "$waitFlag" = "1" ]; then
            echo "${now} wait flag found for charge point #${chargePoint}"
            # charge point busy, locktime passed and waiting for end of charge to disable charge point
            if [ $time = "$unlockTime" ]; then
                # auto unlock time is now, so delete possible wait-to-lock-flag
                echo "0" > $flagFilename
            else
                # unlock time not reached and waiting for auto lock
                # check if charge point still busy to deactivate
                checkDisableLp
            fi
        else
            # not waiting for disabling, so check if autolock time arrived
            if [ $time = "$lockTime" ]; then
                # auto lock time is now
                if [ $waitUntilFinished = "on" ]; then
                    # but if charging is ongoing, wait until finished
                    # so set flag to wait for charge point ending ongoing charging process
                    echo "1" > $flagFilename
                    echo "${now} set wait flag for charge point #${chargePoint}"
                    # check if charge point still busy to deactivate
                    checkDisableLp
                else
                    # disable charge point immediately
                    mqttTopic="openWB/set/lp$chargePoint/ChargePointEnabled"
                    mosquitto_pub -r -t $mqttTopic -m 0
                    echo "${now} auto-disabled charge point #${chargePoint} without wait"
                fi
            fi
        fi
    else
        if [ $time = "$unlockTime" ]; then
            # charge point disabled and auto unlock time is now, so enable charge point
            mqttTopic="openWB/set/lp$chargePoint/ChargePointEnabled"
            mosquitto_pub -r -t $mqttTopic -m 1
            echo "${now} auto-enabled charge point #${chargePoint}"
        fi
    fi
done