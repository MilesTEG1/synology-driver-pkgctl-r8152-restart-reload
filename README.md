# Script for reload or restart the pkgctl-r8152 driver for USB-ETH 2,5 GBps adaptator

This script is linked to this repository : https://github.com/bb-qq/r8152
Thanks to its author for the driver.

Tested on my DS920+ with DSM 7.1.1-42962 Update 4.

In order to use the script, I suggest to create 2 tasks in DSM tasks manager:
1. One launched at every boot/reboot of the NAS;
2. Another launched every 5 or 10 minutes, in order to ensure the driver is working fine.
