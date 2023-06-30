# Script for reload or restart the pkgctl-r8152 driver for USB-ETH 2,5 GBps adaptator

This script is linked to this repository : <https://github.com/bb-qq/r8152>
Thanks to its author for the driver.

Tested on my DS920+ with:
  - DSM 7.1.1-42962 Update 5
  - DSM 7.1.1-42962 Update 6
  - DSM 7.2-64570
  - DSM 7.2-64570 Update 1

<br>

------------

<br>

## 1. Usage (without any arguments or with `--help` or `-h`)

```
Usage: driver-pkgctl-r8152-restart-reload.sh {boot|task|manual} [--notify]

      {boot|task|manual} : Launch mode, mandatory
                           boot       set script to a launch after boot
                           task       set script to a task manager schedule launch
                           manual     set script to a manual launch (from CLI)

      -n, --notify         [Optionnal, always send gotify notification]
      -r, --reactivate_all_down_ethX [Optional, and do only reactivation of all ethX interfaces it find with ip link]
```

<br>

------------

<br>

## 2. Autmaticaly run the script with Task manager in DSM

In order to use the script automatically, I suggest to create 2 tasks in DSM tasks manager:

1. One launched at every boot/reboot of the NAS:
   Use this command :

   ```bash
   bash driver-pkgctl-r8152-restart-reload.sh boot
   ```

2. Another launched every 30 minutes, in order to ensure the driver is working fine.
   Use this command :

   ```bash
   bash driver-pkgctl-r8152-restart-reload.sh task
   ```

<br>

------------

<br>

## 3. Manual use

If you want to launch it manually from the terminal, use :
```bash
bash driver-pkgctl-r8152-restart-reload.sh manual
```

You can also force gotify notifications with `-n` or `--notify` :
```bash
bash driver-pkgctl-r8152-restart-reload.sh manual -n
```

<br>

------------

<br>

## 4. Reactivate all deactivated interface

If you want to ractivate all your deactivated interface, use:
```shell
   bash driver-pkgctl-r8152-restart-reload.sh manual --reactivate_all_down_ethX
```