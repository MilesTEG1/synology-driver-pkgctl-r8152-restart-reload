# Script for reload or restart the pkgctl-r8152 driver for USB-ETH 2,5 GBps adaptator

This script is linked to this repository : <https://github.com/bb-qq/r8152>
Thanks to its author for the driver.

Tested on my DS920+ with DSM 7.1.1-42962 Update 5.

In order to use the script, I suggest to create 2 tasks in DSM tasks manager:

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

3. If you want to launch it manually from the terminal, use :

   ```bash
   bash driver-pkgctl-r8152-restart-reload.sh manual
   ```
