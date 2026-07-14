#!/usr/bin/env python3
"""Selectively mute physical keyboards so kanata can own them.

For event nodes belonging to KEYBOARDS (Vendor:Product from
/proc/bus/input/devices), do not forward via qubes-input-sender.
All other nodes exec the real sender unchanged.
"""

# Put your keyboard ids here (4-digit hex Vendor:Product)
KEYBOARDS = [
    "0001:0001",
]

QUBES_INPUT_SENDER = "/usr/bin/qubes-input-sender"

import os
import sys
import time


def get_infoline(infolines, prefix):
    for line in infolines:
        if line.startswith(prefix + ":"):
            return line
    return None


def main():
    if len(sys.argv) != 4:
        print(
            f"usage: {sys.argv[0]} <rpc> <input-device> <target-domain>",
            file=sys.stderr,
        )
        sys.exit(2)

    _, arg_rpc, arg_input, arg_domain = sys.argv

    with open("/proc/bus/input/devices") as f:
        deviceinfo = f.read()

    inputs = []
    for device in deviceinfo.split("\n\n"):
        infolines = device.split("\n")
        I_line = get_infoline(infolines, "I")
        if not I_line:
            continue

        vendor_pos = I_line.find("Vendor=")
        product_pos = I_line.find("Product=")
        if vendor_pos < 0 or product_pos < 0:
            continue
        vendor = I_line[vendor_pos + 7 : vendor_pos + 11]
        product = I_line[product_pos + 8 : product_pos + 12]
        if f"{vendor}:{product}" not in KEYBOARDS:
            continue

        S_line = get_infoline(infolines, "S")
        if not S_line:
            continue
        sysfs_pos = S_line.find("Sysfs=")
        if sysfs_pos < 0:
            continue
        sysfs = S_line[sysfs_pos + 6 :]
        sysfs_path = f"/sys{sysfs}"
        try:
            sysfs_files = os.listdir(sysfs_path)
        except OSError as e:
            print(f"WARN: cannot list {sysfs_path}: {e}", file=sys.stderr)
            continue
        event_files = [n for n in sysfs_files if n.startswith("event")]
        inputs.extend(event_files)
        print(
            f"INFO: Found keyboard {vendor}:{product} with"
            f" {len(event_files)} events: {' '.join(event_files)}"
        )

    input_paths = [f"/dev/input/{n}" for n in inputs]

    if arg_input in input_paths:
        print("INFO: Not launching input-sender (kanata owns this device)")
        # Hold the unit open without spinning the CPU.
        while True:
            time.sleep(3600)

    print(f"INFO: Launching {QUBES_INPUT_SENDER}")
    os.execvp(
        QUBES_INPUT_SENDER,
        [QUBES_INPUT_SENDER, arg_rpc, arg_input, arg_domain],
    )


if __name__ == "__main__":
    main()
