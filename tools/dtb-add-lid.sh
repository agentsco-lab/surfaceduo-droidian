#!/bin/sh
# The Duo's fold sensor as the kernel's lid switch:
#
#   ./tools/dtb-add-lid.sh <stock.dtb> <out.dtb>
#
# The hall sensor on TLMM GPIO 121 (1 open, 0 fully closed) becomes a
# gpio-keys device "Surface Duo Lid" giving SW_LID, and a wakeup source:
# opening the Duo wakes it from sleep. GPIO 121 is routed to the PDC
# (pinctrl-sm8150.c, {121, 569}), so it can; the wake arrives through the
# AOP and the kernel names glink/smp2p as the cause. Read through sysfs,
# as sfduo-lid-daemon did, it woke nothing - the phone slept on until a
# modem or Wi-Fi wake, or the power key.
#
# A node of its own (/soc/lid_keys): the stock dtbo, applied by the
# bootloader, makes /soc/gpio_keys (the volume key) and leaves this one be.
# sfduo-lid-daemon reads the lid from it when it is there.
set -e
IN=$1; OUT=$2
[ -f "$IN" ] && [ -n "$OUT" ] || { echo "usage: $0 <stock.dtb> <out.dtb>" >&2; exit 1; }
TLMM=$(fdtget -t x "$IN" /soc/pinctrl@03000000 phandle)
cp "$IN" "$OUT"
fdtput -c "$OUT" /soc/lid_keys /soc/lid_keys/lid
fdtput -t s "$OUT" /soc/lid_keys compatible gpio-keys
fdtput -t s "$OUT" /soc/lid_keys label "Surface Duo Lid"
fdtput -t s "$OUT" /soc/lid_keys/lid label lid
fdtput -t x "$OUT" /soc/lid_keys/lid gpios "$TLMM" 79 1     # GPIO 121, active low
fdtput -t u "$OUT" /soc/lid_keys/lid linux,input-type 5     # EV_SW
fdtput -t u "$OUT" /soc/lid_keys/lid linux,code 0           # SW_LID
fdtput -t u "$OUT" /soc/lid_keys/lid debounce-interval 20
fdtput -t x "$OUT" /soc/lid_keys/lid wakeup-source
echo "lid switch added: $OUT"
