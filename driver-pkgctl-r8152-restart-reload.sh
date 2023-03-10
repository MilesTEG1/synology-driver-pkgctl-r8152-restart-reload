#!/bin/bash

# Sources of ideas I used :
#   - https://stackoverflow.com/a/932187/17694638
#   - https://stackoverflow.com/a/48229061/17694638

# ╔════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                                                                        ║
# ║   Script for reload or restart the pkgctl-r8152 driver for USB-ETH 2,5 GBps adaptator  ║
# ║                                 for Synology NAS                                       ║
# ║                                 ----------------                                       ║
# ╚════════════════════════════════════════════════════════════════════════════════════════╝

#  /!\ Need to be launched in root mode in SSH CLI, or in the task planner in DSM
#
# chmod 760 ./driver-pkgctl-r8152-restart-reload.sh
#
# In order to use the script, I suggest to create 2 tasks in DSM tasks manager :
#   1. One launched at every boot/reboot of the NAS
#   2. Another launched every 5 or 10 minutes, in order to ensure the driver is working fine

#
# ====================================================================================== #
# ============================= Variables needed to be set ============================= #
# ====================================================================================== #

#   Set to no for no IPV6, or yes to let IPv6 activated
IPV6="no"

#   Set to the interface you want to check : eth0 or eth1, or eth2 ...
#   In Synology NAS :
#       - eth0 = LAN1
#       - eth1 = LAN2
#       - eth2 = LAN3
#       - eth3 = LAN4
INTERFACE="eth2"

#   Set the Gateway to test (could be whatever IP address you want to ping)
#   or let the script determine the default gateway set by setting the value to "".
GATEWAY=""
# GATEWAY="192.168.2.203"

# ====================================================================================== #
# ========================= Functions needed by the main script ======================== #
# ====================================================================================== #

function get_status() { # Get status from the pkgctl-r8152 driver

    ACTIVE_STATUS=$(synosystemctl get-active-status pkgctl-r8152)
    LOAD_STATUS=$(synosystemctl get-load-status pkgctl-r8152)
    ENABLE_STATUS=$(synosystemctl get-enable-status pkgctl-r8152)

    # Test if the status above are normal :
    #       - ACTIVE_STATUS must be "active"
    #       - LOAD_STATUS must be "loaded"
    #       - ENABLE_STATUS must be "enabled"
    printf "\npkgctl-r8152 ACTIVE_STATUS = %s\n" $ACTIVE_STATUS
    printf "pkgctl-r8152 LOAD_STATUS = %s\n" $LOAD_STATUS
    printf "pkgctl-r8152 ENABLE_STATUS = %s\n\n" $ENABLE_STATUS
    if [[ "${ACTIVE_STATUS}" != "active" ]] || [[ "${LOAD_STATUS}" != "loaded" ]] || [[ "${ENABLE_STATUS}" != "enabled" ]]; then
        # The driver need to be restarted or reloaded
        return 1
    else
        # The driver is well started and loaded
        return 0
    fi
}

function driver_restart_reload() {
    # Restart or reload the driver
    synosystemctl reload-or-restart pkgctl-r8152

    # For the record, here some synosystemctl commands:
    #   start [--no-block] NAME...              Start (activate) one or more units
    #   stop [--no-block] NAME...               Stop (deactivate) one or more units
    #   restart [--no-block] NAME...            Start or restart one or more units
    #   try-restart [--no-block] NAME...        Restart one or more units if active
    #   reload [--no-block] NAME...             Reload one or more units
    #   reload-or-restart [--no-block] NAME...  Reload or restart one or more units
    #   get-enable-status NAME                  Get the enable status of given unit
    #   get-active-status NAME                  Get the active status of given unit
    #   get-load-status NAME                    Get the load status of given unit

    # Disable IPv6
    if [[ "${IPV6}" == "no" ]]; then
        printf "Deactivation of IPv6 on interface %s\n" $INTERFACE
        ip -6 addr flush $INTERFACE
    fi
}

function ping_gateway() { # Check gateway availability to ping

    # Checking if the GATEWAY is set to a value or not.
    # If not, this will determine the default gateway
    if [[ -z "${GATEWAY}" ]]; then
        GATEWAY=$(ip r | grep default | cut -d ' ' -f 3)
    fi

    if [ -z "$GATEWAY" ]; then
        printf "\nError ! No gateway found with the 'ip r' command...\n"
        return 99
    else
        printf "Gateway is = %s\n" $GATEWAY
        ping -I $INTERFACE -q -t 2 -c 1 $GATEWAY >/dev/null && return 0 || return 1
    fi
}

# ====================================================================================== #
# ===================================== Main script ==================================== #
# ====================================================================================== #

# I assume that just after the boot, the driver may be not loaded for various reasons...
# Or after some time, the driver may fail, and the connectivity won't work anymore.
# This will check the connectivity to the gateway/ip provided, and the decide what to do

ping_gateway
RESULT=$?

if [[ $RESULT -eq 0 ]]; then
    printf "Gateway $GATEWAY is accessible ! No need to do something more.\n"
    # No need to do something more
elif [[ $RESULT -eq 1 ]]; then
    printf "Gateway %s IS NOT accessible !\nThe driver need to be restarted or reloaded !\n" $GATEWAY
    driver_restart_reload
else
    printf "Unknown error ! code = %d\n" $RESULT
fi
exit $RESULT

# ====================================================================================== #
# ===================================== Script END ===================================== #
# ====================================================================================== #