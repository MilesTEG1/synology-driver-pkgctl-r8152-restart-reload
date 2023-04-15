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

# ~~~~~ Arguments passed to the script ~~~~ #
NB_PARAM=$#
ARG1=$1
ARG2=$2
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

# ~~~~~~~~~~ Check if root access ~~~~~~~~~ #
if [[ "$EUID" = 0 ]]; then
    echo "(1) already root"
else
    echo "You're not root... sudoing now..."
    sudo -k # make sure to ask for password on next sudo
    if sudo true; then
        echo "(2) correct password"
    else
        echo "(3) wrong password"
        exit 1
    fi
fi
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

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

## Variables Gotify
GOTIFY_URL=https://gotify.ndd.tld
GOTIFY_TOKEN=xxxx-token-xxx
# ====================================================================================== #

# ====================================================================================== #
# ====================== Some variables needed, but not to touch ! ===================== #
# ====================================================================================== #
DRIVER_OK_KO=""
ITERATION_status=0
ITERATION_ping=0

## Variables Gotify
GOTIFY_PRIORITY_SUCCESS=2
GOTIFY_PRIORITY_ERROR=4
GOTIFY_PRIORITY_FAIL=8

#Default values
GOTIFY_PRIORITY=${GOTIFY_PRIORITY_ERROR}
MESSAGE=""
TITLE="Script : $(basename "$0")"
MODE=""
GOTIFY_ALWAYS=""
# ====================================================================================== #

# ====================================================================================== #
# ======================= Check parameters and command line help ======================= #
# ====================================================================================== #
display_help() {
    echo "Usage: $(basename "$0") {boot|task|manual} [--notify]" >&2
    echo
    echo "      {boot|task|manual} : Launch mode, mandatory"
    echo "                           boot       set script to a launch after boot"
    echo "                           task       set script to a task manager schedule launch"
    echo "                           manual     set script to a manual launch (from CLI)"
    echo
    echo "      -n, --notify         [Optionnal, always send gotify notification]"
    echo
    # echo some stuff here for the -a or --add-options
    exit 1
}

if [[ NB_PARAM -gt 2 || NB_PARAM -eq 0 ]]; then
    display_help
else
    case $ARG1 in
    -h | --help)
        display_help
        ;;
    boot)
        MODE="boot"
        ;;
    task)
        MODE="task"
        ;;
    manual)
        MODE="manual"
        ;;
        # ... (same format for other required arguments)
    *)
        echo "Unknown 1st parameter passed: $1"
        display_help
        ;;
    esac
fi

if [[ "${ARG2}" == "--notify" ]] || [[ "${ARG2}" == "-n" ]]; then
    GOTIFY_ALWAYS="OUI"
elif [[ "${ARG2}" != "--notify" ]] && [[ -n "${ARG2}" ]]; then
    echo "Unknown 2nd parameter passed: $1"
    display_help
elif [[ -z "${ARG2}" ]]; then
    GOTIFY_ALWAYS="NON"
fi

if [[ "${MODE}" == "boot" ]] || [[ "${MODE}" == "manual" ]]; then
    GOTIFY_ALWAYS="OUI"
elif [[ "${MODE}" == "task" ]]; then
    GOTIFY_ALWAYS="NON"
fi

# DEBUG
# echo "Parameter n°1 = $ARG1"
# echo "Parameter n°2 = $ARG2"
# echo "MODE = $MODE"
# echo "GOTIFY_ALWAYS = $GOTIFY_ALWAYS"
# ====================================================================================== #

# ====================================================================================== #
# ========================= Functions needed by the main script ======================== #
# ====================================================================================== #
function send_gotify_notification() {
    # On va envoyer une notification toutes les 2 heures si tout va bien pour le pilote
    # Sinon la notification partira quoiqu'il arrive.
    # Vérification de l'heure : heure paire notification, heure impaire pas de notification
    HEURE=$(date +"%H")
    MINUTES=$(date +"%M")
    HEURE_PAIRE=""
    MINUTES_ZERO=""
    [[ $((HEURE % 2)) -eq 0 ]] && HEURE_PAIRE="OUI" || HEURE_PAIRE="NON"
    [[ $MINUTES -eq 0 ]] && MINUTES_ZERO="OUI" || MINUTES_ZERO="NON"

    # Si heure paire et GOTIFY_PRIORITY_SUCCESS, ou bien si GOTIFY_PRIORITY_ERROR ou GOTIFY_PRIORITY_FAIL, on envoi une notification
    if [[ "${GOTIFY_ALWAYS}" == "OUI" ]] || [ ${GOTIFY_PRIORITY} -eq ${GOTIFY_PRIORITY_ERROR} ] || [ ${GOTIFY_PRIORITY} -eq ${GOTIFY_PRIORITY_FAIL} ] || { [ ${GOTIFY_PRIORITY} -eq ${GOTIFY_PRIORITY_SUCCESS} ] && [[ "${HEURE_PAIRE}" == "OUI" ]] && [[ "MINUTES_ZERO" == "OUI" ]]; }; then
        URL="${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}"
        printf "\n\tSending Gotify Notification...\n"
        /usr/bin/curl -s -S --data '{"message": "'"${MESSAGE}"'", "title": "'"${TITLE}"'", "priority":'"${GOTIFY_PRIORITY}"', "extras": {"client::display": {"contentType": "text/markdown"}}}' -X POST -H Content-Type:application/json "${URL}" &>/dev/null
        printf "\n"
    fi
}

function driver_restart_reload() {
    # Restart or reload the driver
    # sudo synosystemctl reload-or-restart pkgctl-r8152
    echo ""
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
}

function disable_ipv6() {
    _INTERFACE=$1
    # Disable IPv6
    if [[ "${IPV6}" == "no" ]] && [[ $(cat /proc/net/if_inet6 | grep $_INTERFACE) != "" ]]; then
        printf "\tDeactivation of IPv6 on interface %s in 5s...\n" $_INTERFACE
        MESSAGE="$MESSAGE\tDeactivation of IPv6 on interface $_INTERFACE in 5s...\n"
        sleep 5s
        sudo ip -6 addr flush $_INTERFACE
    fi
}

function get_status() { # Get status from the pkgctl-r8152 driver

    ITERATION_status=$((ITERATION_status + 1))

    ACTIVE_STATUS=$(sudo synosystemctl get-active-status pkgctl-r8152)
    LOAD_STATUS=$(sudo synosystemctl get-load-status pkgctl-r8152)
    ENABLE_STATUS=$(sudo synosystemctl get-enable-status pkgctl-r8152)

    PACKAGE_VERSION=$(sudo synopkg version r8152)
    PACKAGE_ONOFF=$(sudo synopkg is_onoff r8152)

    # Test if the status above are normal :
    #       - ACTIVE_STATUS must be "active"
    #       - LOAD_STATUS must be "loaded"
    #       - ENABLE_STATUS must be "enabled"
    printf "\t"
    printf %s "$PACKAGE_ONOFF"
    printf " , version is %s\n" $PACKAGE_VERSION

    printf "\n\tpkgctl-r8152 ACTIVE_STATUS = %s\n" $ACTIVE_STATUS
    printf "\tpkgctl-r8152 LOAD_STATUS = %s\n" $LOAD_STATUS
    printf "\tpkgctl-r8152 ENABLE_STATUS = %s\n\n" $ENABLE_STATUS

    MESSAGE="$MESSAGE\t\n\tpkgctl-r8152 ACTIVE_STATUS = $ACTIVE_STATUS\n"
    MESSAGE="$MESSAGE\tpkgctl-r8152 LOAD_STATUS = $LOAD_STATUS\n"
    MESSAGE="$MESSAGE\tpkgctl-r8152 ENABLE_STATUS = $ENABLE_STATUS\n\n"

    if [[ "${ACTIVE_STATUS}" != "active" ]] || [[ "${LOAD_STATUS}" != "loaded" ]] || [[ "${ENABLE_STATUS}" != "enabled" ]]; then
        # The driver need to be restarted or reloaded
        printf "\tThe driver status AREN'T OK !\n\tThe driver need to be restarted or reloaded !\n"
        MESSAGE="$MESSAGE\tThe driver status AREN'T OK !\n\tThe driver need to be restarted or reloaded !\n"
        DRIVER_OK_KO="KO"
    elif [[ "${ACTIVE_STATUS}" = "active" ]] && [[ "${LOAD_STATUS}" = "loaded" ]] && [[ "${ENABLE_STATUS}" = "enabled" ]]; then
        # The driver is well started and loaded
        printf "\tThe driver status are OK ! No need to do something more.\n"
        MESSAGE="$MESSAGE\tThe driver status are OK ! No need to do something more.\n"
        # No need to do something more here
    else
        printf "\tUnknown error with get_status() ! code = %d\n" $RESULT
        MESSAGE="$MESSAGE\tUnknown error with get_status() ! code = $RESULT\n"
        send_gotify_notification
        exit 1
    fi
}

function ping_gateway() { # Check gateway availability to ping

    ITERATION_ping=$((ITERATION_ping + 1))

    # Checking if the GATEWAY is set to a value or not.
    # If not, this will determine the default gateway
    if [[ -z "${GATEWAY}" ]]; then
        GATEWAY=$(sudo ip r | grep default | cut -d ' ' -f 3)
    fi

    if [ -z "$GATEWAY" ]; then
        printf "\n\tError ! No gateway found with the 'ip r' command...\n"
        MESSAGE="$MESSAGE\n\tError ! No gateway found with the 'ip r' command...\n"

        send_gotify_notification
        exit 99
    else
        printf "\tGateway is = %s\n" $GATEWAY
        MESSAGE="$MESSAGE\tGateway is = $GATEWAY\n"

        sudo ping -I $INTERFACE -q -t 2 -c 1 $GATEWAY >/dev/null && PING="OK" || PING="not-OK"
    fi

}

function reactivate_eth0() {
    sudo ifconfig eth0 up
    disable_ipv6 eth0
    eth0_IP=$(ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    printf "\n\teth0 should be up now. You can connect the NAS on %s in order to sort things out...\nExiting script now.\n" $eth0_IP
    MESSAGE="$MESSAGE\n\teth0 should be up now. You can connect the NAS on $eth0_IP in order to sort things out...\nExiting script now.\n"
    GOTIFY_PRIORITY=${GOTIFY_PRIORITY_FAIL}
    send_gotify_notification
    exit 1
}

function deactivate_eth0_if_up() {
    # Test if eth0 is already down or still up
    if [[ -n "$(ip a show eth0 up)" ]]; then
        printf "\n\teth0 is still up and running. Shutting down now.\n"
        MESSAGE="$MESSAGE\n\teth0 is still up and running. Shutting down now.\n"
        sudo ifconfig eth0 down
    else
        printf "\n\teth0 is already down.\n"
        MESSAGE="$MESSAGE\n\teth0 is already down.\n"
    fi

}

# ====================================================================================== #
# ===================================== Main script ==================================== #
# ====================================================================================== #

# I assume that just after the boot, the driver may be not loaded for various reasons...
# Or after some time, the driver may fail, and the connectivity won't work anymore.
# This will check the connectivity to the gateway/ip provided, and the decide what to do

PING=""
# We will try 2 times to restart the driver if it has failed.
for ((i = 1; i < 3; i++)); do
    printf "Try n°%i\n" ${i}

    get_status

    if [[ "${DRIVER_OK_KO}" == "KO" ]]; then
        # The driver status AREN'T OK !
        # The driver need to be restarted or reloaded !
        if ((i == 2)); then
            # We are on the 2nd try, and the driver is still not OK !
            printf "\n\tThe driver is still not OK on the 2nd try !\nThat's not good...\nIt means the %s isn't working... So let's reactivate the eth0 interface." $INTERFACE
            MESSAGE="$MESSAGE\n\tThe driver is still not OK on the 2nd try !\nThat's not good...\nIt means the $INTERFACE isn't working... So let's reactivate the eth0 interface."
            reactivate_eth0
        fi

        driver_restart_reload

    else
        # The driver status is OK !
        # Let's try the ping function
        ping_gateway
        if [[ "${PING}" == "not-OK" ]]; then
            # Ping isn't OK...
            if ((i == 1)); then
                # This is the first run
                printf "\tGateway %s IS NOT accessible !\n\tThe driver need to be restarted or reloaded !\n" $GATEWAY
                MESSAGE="$MESSAGE\tGateway $GATEWAY IS NOT accessible !\n\tThe driver need to be restarted or reloaded !\n"
                DRIVER_OK_KO="KO"
                driver_restart_reload
            else
                # This is the 2nd run
                printf "\tThis is the second try, and the ping on this try isn't OK... \nIt means the %s isn't working... So let's reactivate the eth0 interface." $INTERFACE
                MESSAGE="$MESSAGE\tThis is the second try, and the ping on this try isn't OK... \nIt means the $INTERFACE isn't working... So let's reactivate the eth0 interface."
                reactivate_eth0
            fi

        else
            # Ping is OK
            if ((i == 1)); then
                # This is the first run
                printf "\tGateway %s is accessible ! No need to do something more.\n" $GATEWAY
                MESSAGE="$MESSAGE\tGateway $GATEWAY is accessible !\t\nNo need to do something more.\n"
                disable_ipv6 $INTERFACE
                deactivate_eth0_if_up
                GOTIFY_PRIORITY=${GOTIFY_PRIORITY_SUCCESS}
                send_gotify_notification
                exit 0
            else
                # This is the 2nd run
                printf "\tGateway %s is now accessible (on the 2nd run) !\nNote : the status wasn't OK before...\n" $GATEWAY
                MESSAGE="$MESSAGE\tGateway $GATEWAY is accessible !\t\nNo need to do something more.\n"
                disable_ipv6 $INTERFACE
                deactivate_eth0_if_up
                GOTIFY_PRIORITY=${GOTIFY_PRIORITY_ERROR}
                send_gotify_notification
                exit 1
            fi
        fi
    fi
done
