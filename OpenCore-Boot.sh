#!/usr/bin/env bash

# Special thanks to:
# https://github.com/Leoyzen/KVM-Opencore
# https://github.com/thenickdude/KVM-Opencore/
# https://github.com/qemu/qemu/blob/master/docs/usb2.txt
#
# qemu-img create -f qcow2 mac_hdd_ng.img 128G
#
# echo 1 > /sys/module/kvm/parameters/ignore_msrs (this is required)

###############################################################################
# NOTE: Tweak the "MY_OPTIONS" line in case you are having booting problems!
###############################################################################
#
# Change `Penryn` to `Haswell-noTSX` in OpenCore-Boot.sh file for macOS Sonoma!
#
###############################################################################


MY_OPTIONS="+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check"

# This script works for Big Sur, Catalina, Mojave, and High Sierra. Tested with
# macOS 10.15.6, macOS 10.14.6, and macOS 10.13.6.

ALLOCATED_RAM="10240" # MiB
CPU_SOCKETS="1"
CPU_CORES="4"
CPU_THREADS="4"

REPO_PATH="."
OVMF_DIR="."

# shellcheck disable=SC2054
args=(
  -enable-kvm -m "$ALLOCATED_RAM" -cpu Haswell-noTSX,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,"$MY_OPTIONS"
  -machine q35
  -device qemu-xhci,id=xhci
  -device usb-kbd,bus=xhci.0 -device usb-tablet,bus=xhci.0
  -smp "$CPU_THREADS",cores="$CPU_CORES",sockets="$CPU_SOCKETS"
  -device usb-ehci,id=ehci
  -device usb-host,bus=ehci.0,vendorid=0x05ac,id=iphone,guest-reset=false
  # -device usb-kbd,bus=ehci.0
  # -device usb-mouse,bus=ehci.0
  # -device nec-usb-xhci,id=xhci
  # -global nec-usb-xhci.msi=off
  # -global ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off
  # -device usb-host,vendorid=0x8086,productid=0x0808  # 2 USD USB Sound Card
  # -device usb-host,vendorid=0x1b3f,productid=0x2008  # Another 2 USD USB Sound Card
  -device isa-applesmc,osk="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"
  -drive if=pflash,format=raw,readonly=on,file="$REPO_PATH/$OVMF_DIR/OVMF_CODE.fd"
  -drive if=pflash,format=raw,file="$REPO_PATH/$OVMF_DIR/OVMF_VARS-1920x1080.fd"
  -smbios type=2
  -device ich9-intel-hda -device hda-duplex
  -device ich9-ahci,id=sata
  # -drive id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file="$REPO_PATH/OpenCore/OpenCore.qcow2"
  # -device ide-hd,bus=sata.1,drive=OpenCoreBoot
  # -device ide-hd,bus=sata.3,drive=InstallMedia
  # -drive id=InstallMedia,if=none,file="$REPO_PATH/BaseSystem.img",format=raw
  -drive id=MacHDD,if=none,file="$HOME/QemuVM/SequoiaHDD.img",format=qcow2
  -device ide-hd,bus=sata.2,drive=MacHDD
  # -netdev tap,id=net0,ifname=tap0,script=no,downscript=no -device virtio-net-pci,netdev=net0,id=net0,mac=52:54:00:c9:18:27
  # Connects to host, internet; Working with 10.0.2.15 ip
  # -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=net0,id=net0,mac=52:54:00:c9:18:27 
  # Connects to host, lan, internet; Working with 192.168.122.155 ip
  # You might need to give permissions to qemu-bridge-helper as chmod u+s qemu-bridge-helper
  -netdev bridge,id=net0,br=virbr0,"helper=/usr/lib/qemu/qemu-bridge-helper" -device virtio-net-pci,netdev=net0,id=net0,mac=00:16:CB:00:11:34
  # -netdev user,id=net0 -device vmxnet3,netdev=net0,id=net0,mac=52:54:00:c9:18:27  # Note: Use this line for High Sierra
  -device vmware-svga
  -monitor stdio
  # -spice port=5900,addr=127.0.0.1,disable-ticketing=on
  -rtc base=localtime,clock=host
)

set -e

# -----------------------------------------------------------------------------
# Prepare libvirt bridge
# -----------------------------------------------------------------------------

QEMU_HELPER="/usr/lib/qemu/qemu-bridge-helper"

# Fix bridge helper permissions if required
if [ ! -u "$QEMU_HELPER" ]; then
    echo "Setting qemu-bridge-helper permissions..."
    sudo chmod u+s "$QEMU_HELPER"
fi

# Start libvirt default network if needed
if ! virsh net-info default 2>/dev/null | grep -q "Active:.*yes"; then
    echo "Starting libvirt default network..."
    sudo virsh net-start default >/dev/null
fi

# Wait until virbr0 exists
for i in {1..10}; do
    if ip link show virbr0 >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

if ! ip link show virbr0 >/dev/null 2>&1; then
    echo "ERROR: virbr0 was not created."
    exit 1
fi

# Enable Avahi daemon if not running (for Bonjour support)
if ! systemctl is-active --quiet avahi-daemon; then
    sudo systemctl start avahi-daemon
fi

# -----------------------------------------------------------------------------
# Cleanup function to stop libvirt network on exit
# -----------------------------------------------------------------------------
cleanup() {
    echo "Stopping libvirt network..."
    sudo virsh net-destroy default >/dev/null 2>&1 || true
}

trap cleanup EXIT

qemu-system-x86_64 "${args[@]}"
