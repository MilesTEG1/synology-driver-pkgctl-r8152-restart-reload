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
nb_param=$#
arg1=$1
arg2=$2
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

# ====================================================================================== #
# ============================= Variables needed to be set ============================= #
# ====================================================================================== #

#   Set to no for no ipv6, or yes to let ipv6 activated (global parameter: it's for all interfaces)
ipv6="no"

#   Set to the interface in 2,5G/5G you want to check : eth0 or eth1, or eth2 ...
#   In Synology NAS :
#       - eth0 = LAN1
#       - eth1 = LAN2
#       - eth2 = LAN3
#       - eth3 = LAN4
interface="eth2"

# Add embedded interfaces you want to disable when $interface is up and running correctly
# and enable when $interface isn't working correctly.
# Choose wisely!
embedded_interface_to_deactivate=("eth0" "eth1")

#   Set the gateway to test (could be whatever IP address you want to ping)
#   or let the script determine the default gateway set by setting the value to "".
gateway=""
# gateway="192.168.2.203"

## Variables Gotify

# Set gotify_notif to   false to disable gotify notification
#                       true to enable gotify notification
gotify_notif=true

gotify_url=https://gotify.ndd.tld
gotify_token=xxxx-token-xxx

# ====================================================================================== #

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
# ====================== Some variables needed, but not to touch ! ===================== #
# ====================================================================================== #
driver_ok_ko=""
iteration_status=0
iteration_ping=0

## Variables Gotify
gotify_priority_success=2
gotify_priority_error=4
gotify_priority_fail=8

#Default values
gotify_priority=${gotify_priority_error}
message=""
title="Script : $(basename "$0")"
mode=""
gotify_always=""
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

if [[ nb_param -gt 2 || nb_param -eq 0 ]]; then
    display_help
else
    case $arg1 in
    -h | --help)
        display_help
        ;;
    boot)
        mode="boot"
        ;;
    task)
        mode="task"
        ;;
    manual)
        mode="manual"
        ;;
        # ... (same format for other required arguments)
    *)
        echo "Unknown 1st parameter passed: $1"
        display_help
        ;;
    esac
fi

if [[ "${arg2}" == "--notify" ]] || [[ "${arg2}" == "-n" ]]; then
    gotify_always="oui"
elif [[ "${arg2}" != "--notify" ]] && [[ -n "${arg2}" ]]; then
    echo "Unknown 2nd parameter passed: $1"
    display_help
elif [[ -z "${arg2}" ]]; then
    gotify_always="non"
fi

if [[ "${mode}" == "boot" ]] || [[ "${mode}" == "manual" ]]; then
    gotify_always="oui"
elif [[ "${mode}" == "task" ]]; then
    gotify_always="non"
fi

# DEBUG
# echo "Parameter n°1 = $arg1"
# echo "Parameter n°2 = $arg2"
# echo "mode = $mode"
# echo "gotify_always = $gotify_always"
# ====================================================================================== #

# ====================================================================================== #
# ========================= Functions needed by the main script ======================== #
# ====================================================================================== #
function send_gotify_notification() {
    # On va envoyer une notification toutes les 2 heures si tout va bien pour le pilote
    # Sinon la notification partira quoiqu'il arrive.
    # Vérification de l'heure : heure paire notification, heure impaire pas de notification
    #
    if [ "$gotify_notif" = true ]; then
        heure=10#$(date +"%H")
        minutes=10#$(date +"%M")
        heure_paire=""
        minutes_zero=""
        ((heure % 2 == 0)) && heure_paire="oui" || heure_paire="non"
        ((minutes == 0)) && minutes_zero="oui" || minutes_zero="non"

        # Si heure paire et gotify_priority_success, ou bien si gotify_priority_error ou gotify_priority_fail, on envoi une notification

        if [[ "${gotify_always}" == "oui" ]] || [ ${gotify_priority} -eq ${gotify_priority_error} ] || [ ${gotify_priority} -eq ${gotify_priority_fail} ] || { [ ${gotify_priority} -eq ${gotify_priority_success} ] && ((heure % 2 == 0 && minutes == 0)); }; then
            # if [[ "${gotify_always}" == "oui" ]] || [ ${gotify_priority} -eq ${gotify_priority_error} ] || [ ${gotify_priority} -eq ${gotify_priority_fail} ] || { [ ${gotify_priority} -eq ${gotify_priority_success} ] && [[ "${heure_paire}" == "oui" ]] && [[ "${minutes_zero}" == "oui" ]]; }; then
            URL="${gotify_url}/message?token=${gotify_token}"
            printf "\n\tSending Gotify Notification...\n"
            # /usr/bin/curl -s -S --data '{"message": "'"${message}"'", "title": "'"${title}"'", "priority":'"${gotify_priority}"', "extras": {"client::display": {"contentType": "text/markdown"}}}' -X POST -H Content-Type:application/json "${URL}" &>/dev/null
            # In order to accept the escape characters, the post command must be in text/plain
            /usr/bin/curl -s -S -X POST "${URL}" -H "accept: application/json" -H "Content-Type: application/json" --data "{ \"message\": \"${message}\", \"title\": \"${title}\", \"priority\": ${gotify_priority}, \"extras\": {\"client::display\": {\"contentType\": \"text/plain\"}}}" &>/dev/null
            printf "\n"
        fi
    fi
}

function driver_restart_reload() {
    # Restart or reload the driver
    sudo synosystemctl reload-or-restart pkgctl-r8152
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
    # Disable ipv6
    _interface="$1"
    if [[ "${ipv6}" == "no" ]]; then
        if [[ $(cat /proc/net/if_inet6 | grep "${_interface}") != "" ]]; then
            printf "\tDeactivation of ipv6 on interface %s in 5s...\n" "${_interface}"
            message="${message}\tDeactivation of ipv6 on interface ${_interface} in 5s...\n"
            sleep 5s
            sudo ip -6 addr flush "${_interface}"
        else
            printf "\tIpv6 on interface %s is already deactivated.\n" "${_interface}"
            message="${message}\tIpv6 on interface ${_interface} is already deactivated.\n"
        fi
    fi

}

function get_status() { # Get status from the pkgctl-r8152 driver

    iteration_status=$((iteration_status + 1))

    active_status=$(sudo synosystemctl get-active-status pkgctl-r8152)
    load_status=$(sudo synosystemctl get-load-status pkgctl-r8152)
    enable_status=$(sudo synosystemctl get-enable-status pkgctl-r8152)

    package_version=$(sudo synopkg version r8152)
    package_onoff=$(sudo synopkg is_onoff r8152)

    # Test if the status above are normal :
    #       - active_status must be "active"
    #       - load_status must be "loaded"
    #       - enable_status must be "enabled"
    printf "\t"
    printf %s "$package_onoff"
    printf " , version is %s\n" "$package_version"

    printf "\n\tpkgctl-r8152 active_status = %s\n" "$active_status"
    printf "\tpkgctl-r8152 load_status = %s\n" "$load_status"
    printf "\tpkgctl-r8152 enable_status = %s\n\n" "$enable_status"

    message="${message}\t\n\tpkgctl-r8152 active_status = $active_status\n"
    message="${message}\tpkgctl-r8152 load_status = $load_status\n"
    message="${message}\tpkgctl-r8152 enable_status = $enable_status\n\n"

    if [[ "${active_status}" != "active" ]] || [[ "${load_status}" != "loaded" ]] || [[ "${enable_status}" != "enabled" ]]; then
        # The driver need to be restarted or reloaded
        printf "\tThe driver status AREN'T OK !\n\tThe driver need to be restarted or reloaded !\n"
        message="${message}\tThe driver status AREN'T OK !\n\tThe driver need to be restarted or reloaded !\n"
        driver_ok_ko="KO"
    elif [[ "${active_status}" = "active" ]] && [[ "${load_status}" = "loaded" ]] && [[ "${enable_status}" = "enabled" ]]; then
        # The driver is well started and loaded
        printf "\tThe driver status are OK ! No need to do something more.\n"
        message="${message}\tThe driver status are OK ! No need to do something more.\n"
        # No need to do something more here
    else
        printf "\tUnknown error with get_status() ! code = %d\n" "$RESULT"
        message="${message}\tUnknown error with get_status() ! code = $RESULT\n"
        send_gotify_notification
        exit 1
    fi
}

function ping_gateway() { # Check gateway availability to ping

    iteration_ping=$((iteration_ping + 1))

    # Checking if the gateway is set to a value or not.
    # If not, this will determine the default gateway
    if [[ -z "${gateway}" ]]; then
        gateway=$(sudo ip r | grep default | cut -d ' ' -f 3)
    fi

    if [ -z "$gateway" ]; then
        printf "\n\tError ! No gateway found with the 'ip r' command...\n"
        message="${message}\n\tError ! No gateway found with the 'ip r' command...\n"

        send_gotify_notification
        exit 99
    else
        printf "\tgateway is = %s\n" $gateway
        message="${message}\tgateway is = $gateway\n"

        sudo ping -I $interface -q -t 2 -c 1 $gateway >/dev/null && PING="OK" || PING="not-OK"
    fi

}

function reactivate_eth0_ethX() {
    for embedded_interface_i in "${embedded_interface_to_deactivate[@]}"; do
        sudo ifconfig "${embedded_interface_i}" up
        disable_ipv6 "${embedded_interface_i}"
        ethx_IP=$(ip addr show "${embedded_interface_i}" | grep "inet\b" | awk '{print $2}' | cut -d/ -f1) # Thanks to : https://askubuntu.com/a/560466
        printf "\t-> %s should be up now. You can connect the NAS on %s in order to sort things out...\n" "${embedded_interface_i}" "${ethx_IP}"
        message="${message}\n\t-> ${embedded_interface_i} should be up now. You can connect the NAS on ${ethx_IP} in order to sort things out...\n"
    done
    printf "  => Exiting script now.\n"
    message="${message}  => Exiting script now.\n"
    gotify_priority=${gotify_priority_fail}
    send_gotify_notification
    exit 1
}

function deactivate_eth0_ethX_if_up() {
    # Test if eth0...ethX is/are already down or still up
    for embedded_interface_i in "${embedded_interface_to_deactivate[@]}"; do
        if [[ -n "$(ip a show ${embedded_interface_i} up)" ]]; then
            printf "\t%s is still up and running. Shutting down now.\n" "${embedded_interface_i}"
            message="${message}\t${embedded_interface_i} is still up and running. Shutting down now.\n"
            sudo ifconfig "${embedded_interface_i}" down
        else
            printf "\t%s is already down.\n" "${embedded_interface_i}"
            message="${message}\t${embedded_interface_i} is already down.\n"
        fi
    done

}

# ====================================================================================== #
# ===================================== Main script ==================================== #
# ====================================================================================== #

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║ Check if the interfaces to disable aren't including the one we need to   ║
# ║ be up and running                                                        ║
# ╚══════════════════════════════════════════════════════════════════════════╝
message=""
for embedded_interface_i in "${embedded_interface_to_deactivate[@]}"; do
    if [[ "${embedded_interface_i}" == "${interface}" ]]; then
        message="The interface '${embedded_interface_i}' you want disabled is the 2,5G / 5G interface you want to keep up and running.\nReview your settings... Exiting now.\n"
        # printf "%s" "$message"
        printf "The interface '%s' you want disabled is the 2,5G / 5G interface you want to keep up and running.\nReview your settings... Exiting now.\n" "${embedded_interface_i}"
        send_gotify_notification
        exit 1
    fi
done
string_value=$(printf "%s" "${embedded_interface_to_deactivate[*]}")
# printf -v message "%s : will be deactivated if '%s' is up and running.\n" "${string_value[*]// /, }" "${interface}"
message="  => ${string_value[*]// /, } : will be deactivated if '${interface}' is up and running.\n"
printf "  => %s : will be deactivated if '%s' is up and running.\n" "${string_value[*]// /, }" "${interface}"
# ╚══════════════════════════════════════════════════════════════════════════╝

# I assume that just after the boot, the driver may be not loaded for various reasons...
# Or after some time, the driver may fail, and the connectivity won't work anymore.
# This will check the connectivity to the gateway/ip provided, and the decide what to do

PING=""
# We will try 2 times to restart the driver if it has failed.
for ((i = 1; i < 3; i++)); do
    printf "Try n°%i\n" ${i}

    get_status

    if [[ "${driver_ok_ko}" == "KO" ]]; then
        # The driver status AREN'T OK !
        # The driver need to be restarted or reloaded !
        if ((i == 2)); then
            # We are on the 2nd try, and the driver is still not OK !
            printf "\n\tThe driver is still not OK on the 2nd try !\nThat's not good...\nIt means the %s isn't working... So let's reactivate the eth0 interface." $interface
            message="${message}\n\tThe driver is still not OK on the 2nd try !\nThat's not good...\nIt means the ${interface} isn't working... So let's reactivate the eth0 interface."
            reactivate_eth0_ethX
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
                printf "\tGateway %s IS NOT accessible !\n\tThe driver need to be restarted or reloaded !\n" "$gateway"
                message="${message}\tgateway ${gateway} IS NOT accessible !\n\tThe driver need to be restarted or reloaded !\n"
                driver_ok_ko="KO"
                driver_restart_reload
            else
                # This is the 2nd run
                printf "\tThis is the second try, and the ping on this try isn't OK... \nIt means the %s isn't working... So let's reactivate the eth0 interface." $interface
                message="${message}\tThis is the second try, and the ping on this try isn't OK... \nIt means the ${interface} isn't working... So let's reactivate the eth0 interface."
                reactivate_eth0_ethX
            fi

        else
            # Ping is OK
            if ((i == 1)); then
                # This is the first run
                printf "\tgateway %s is accessible ! No need to do something more.\n" "$gateway"
                message="${message}\tgateway ${gateway} is accessible !\t\nNo need to do something more.\n"
                disable_ipv6 ${interface}
                deactivate_eth0_ethX_if_up
                gotify_priority=${gotify_priority_success}
                send_gotify_notification
                exit 0
            else
                # This is the 2nd run
                printf "\tgateway %s is now accessible (on the 2nd run) !\nNote : the status wasn't OK before...\n" "$gateway"
                message="${message}\tgateway $gateway is accessible !\t\nNo need to do something more.\n"
                disable_ipv6 $interface
                deactivate_eth0_ethX_if_up
                gotify_priority=${gotify_priority_error}
                send_gotify_notification
                exit 1
            fi
        fi
    fi
done
