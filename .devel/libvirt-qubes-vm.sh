#!/usr/bin/env bash
#
# qubes-libvirt-provision.sh
#
# Define a libvirt/QEMU-KVM guest suitable for installing Qubes OS as a
# nested (L1) guest, for development and testing. PRELIMINARY: expect to tune.
#
# What it sets up (why):
#   - Q35 chipset + UEFI (OVMF), Secure Boot disabled  vIOMMU needs Q35; the
#                                                       ISO won't boot with SB on
#   - CPU host-passthrough, 1 socket / N cores          exposes vmx/svm to Xen;
#                                                       simple topology is safest
#   - Emulated Intel IOMMU (interrupt remapping,        lets Xen offer PCI
#     caching mode, IOTLB) + split IOAPIC               passthrough to sys-net etc.
#   - e1000 NIC, VGA video, PS/2 input, virtio RNG      choices reported to work;
#                                                       virtio NIC/video reportedly
#                                                       hung sys-net / failed
#   - qcow2 system disk (virtio) + ISO on SATA CD-ROM   CD-ROM boots first
#
# Host requirements: libvirt >= 7.2, QEMU/KVM, OVMF firmware (edk2-ovmf /
# ovmf package), nested virtualization enabled in kvm_intel / kvm_amd.
#
# The config is modelled on a community report of Qubes 4.2 running with HVM
# under KVM/QEMU (forum.qubes-os.org, "Qubes Lab VM, with HVM support, under
# Fedora 37 baremetal using KVM/QEMU"), plus the standard QEMU recipe for a
# nested-KVM vIOMMU (split irqchip, intremap, caching-mode).

set -Eeuo pipefail

readonly PROG=${0##*/}

# ---------------------------------------------------------------- defaults --
NAME=qubes-dev
VCPUS=8
MEM_GIB=32
DISK_GIB=250
POOL=default
NETWORK=default
NIC_MODEL=e1000
VIDEO=vga
IOMMU=intel
USB=yes
CONNECT=qemu:///system
PRINT_XML=no
SKIP_HOST_CHECKS=no
START=no
ISO="/var/lib/libvirt/images/Qubes-R4.3.1-x86_64.iso"

# Set once we have created a volume, so we can roll it back on failure.
VOL=""
CREATED_VOL=no
TMP_XML=""

# ----------------------------------------------------------------- helpers --
log()  { printf '[%s] %s\n' "$PROG" "$*" >&2; }
warn() { printf '[%s] WARNING: %s\n' "$PROG" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$PROG" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $PROG [options] ISO_PATH
       $PROG [options] --iso ISO_PATH

Define a libvirt VM for installing Qubes OS (nested under KVM).

Required:
  ISO_PATH, -i, --iso PATH   Qubes OS installation ISO to attach

Options:
  -n, --name NAME            Domain name                       (default: $NAME)
  -c, --vcpus N              vCPU count (1 socket, N cores)    (default: $VCPUS)
  -m, --memory GIB           RAM in GiB                        (default: $MEM_GIB)
  -d, --disk-size GIB        System disk size in GiB, sparse   (default: $DISK_GIB)
  -p, --pool NAME            Storage pool for the disk         (default: $POOL)
      --network NAME         libvirt network to attach to      (default: $NETWORK)
      --nic-model MODEL      NIC model                         (default: $NIC_MODEL)
      --video vga|qxl        Video model                       (default: $VIDEO)
      --iommu MODE           intel       full: intremap + caching mode + iotlb
                             intel-basic bare <iommu model='intel'/>
                             none        no vIOMMU             (default: $IOMMU)
      --no-usb               Do not attach a USB controller (no sys-usb)
      --connect URI          libvirt connection URI            (default: $CONNECT)
      --start                Start the VM after defining it
      --print-xml            Print the domain XML and exit (touches nothing)
      --skip-host-checks     Skip /dev/kvm and nested-virt checks
  -h, --help                 Show this help

Examples:
  $PROG ~/Downloads/Qubes-R4.2.4-x86_64.iso
  $PROG -n qubes-test -c 12 -m 24 -d 150 --start /srv/iso/Qubes.iso
  $PROG --print-xml --iommu intel-basic Qubes.iso
EOF
}

need_arg() { [[ $# -ge 2 && -n ${2:-} ]] || die "option $1 requires an argument"; }

is_pos_int() { [[ $1 =~ ^[0-9]+$ ]] && ((10#$1 > 0)); }

xml_escape() {
    printf '%s' "$1" | sed \
        -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
        -e "s/'/\&apos;/g" -e 's/"/\&quot;/g'
}

virsh_() { virsh -c "$CONNECT" "$@"; }

cleanup() {
    local rc=$?
    [[ -n $TMP_XML ]] && rm -f -- "$TMP_XML"
    if ((rc != 0)) && [[ $CREATED_VOL == yes ]]; then
        warn "rolling back: deleting volume '$VOL' from pool '$POOL'"
        virsh_ vol-delete --pool "$POOL" "$VOL" >/dev/null 2>&1 || true
    fi
    return "$rc"
}
trap cleanup EXIT

# ------------------------------------------------------------ arg parsing --
while (($#)); do
    case $1 in
        -i|--iso)        need_arg "$@"; ISO=$2;       shift 2 ;;
        -n|--name)       need_arg "$@"; NAME=$2;      shift 2 ;;
        -c|--vcpus)      need_arg "$@"; VCPUS=$2;     shift 2 ;;
        -m|--memory)     need_arg "$@"; MEM_GIB=$2;   shift 2 ;;
        -d|--disk-size)  need_arg "$@"; DISK_GIB=$2;  shift 2 ;;
        -p|--pool)       need_arg "$@"; POOL=$2;      shift 2 ;;
        --network)       need_arg "$@"; NETWORK=$2;   shift 2 ;;
        --nic-model)     need_arg "$@"; NIC_MODEL=$2; shift 2 ;;
        --video)         need_arg "$@"; VIDEO=$2;     shift 2 ;;
        --iommu)         need_arg "$@"; IOMMU=$2;     shift 2 ;;
        --connect)       need_arg "$@"; CONNECT=$2;   shift 2 ;;
        --no-usb)        USB=no;                      shift ;;
        --start)         START=yes;                   shift ;;
        --print-xml)     PRINT_XML=yes;               shift ;;
        --skip-host-checks) SKIP_HOST_CHECKS=yes;     shift ;;
        -h|--help)       usage; exit 0 ;;
        --)              shift
                         if (($# == 1)) && [[ -z $ISO ]]; then ISO=$1; shift; fi
                         break ;;
        -*)              die "unknown option: $1 (see --help)" ;;
        *)               [[ -z $ISO ]] || die "unexpected extra argument: $1"
                         ISO=$1; shift ;;
    esac
done
(($# == 0)) || die "unexpected arguments: $*"

# ------------------------------------------------------------- validation --
[[ -n $ISO ]] || { usage >&2; die "no installation ISO given"; }

[[ $NAME =~ ^[A-Za-z0-9._-]+$ ]] \
    || die "invalid --name '$NAME' (allowed: letters, digits, . _ -)"
is_pos_int "$VCPUS"    || die "--vcpus must be a positive integer"
is_pos_int "$MEM_GIB"  || die "--memory must be a positive integer (GiB)"
is_pos_int "$DISK_GIB" || die "--disk-size must be a positive integer (GiB)"
[[ $NIC_MODEL =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid --nic-model '$NIC_MODEL'"

case $VIDEO in
    vga|qxl) ;;
    *) die "--video must be 'vga' or 'qxl' (virtio video reportedly fails)" ;;
esac
case $IOMMU in
    intel|intel-basic|none) ;;
    *) die "--iommu must be one of: intel, intel-basic, none" ;;
esac

[[ $NIC_MODEL == virtio* ]] \
    && warn "virtio NICs have been reported to hang sys-net under nested Qubes"

[[ -f $ISO ]] || die "ISO not found: $ISO"
[[ -r $ISO ]] || die "ISO not readable: $ISO"
ISO=$(realpath -e -- "$ISO")

if [[ $CONNECT == *:///system* && ( $ISO == /home/* || $ISO == /root/* ) ]]; then
    warn "ISO is under a home directory. With $CONNECT, QEMU runs as an"
    warn "unprivileged service user and may get 'Permission denied' (or be"
    warn "blocked by SELinux/AppArmor). If so, move the ISO to a shared"
    warn "location such as /var/lib/libvirt/images/ or grant access via ACLs."
fi

# ------------------------------------------------------------ host checks --
check_host() {
    command -v virsh >/dev/null 2>&1 \
        || die "virsh not found (install the libvirt client tools)"

    if [[ $SKIP_HOST_CHECKS == no ]]; then
        [[ -e /dev/kvm ]] \
            || die "/dev/kvm missing: enable VT-x/AMD-V in firmware and load the kvm modules"

        local mod param val found=no
        for mod in kvm_intel kvm_amd; do
            param=/sys/module/$mod/parameters/nested
            [[ -r $param ]] || continue
            found=yes
            read -r val <"$param"
            case $val in
                Y|y|1) log "nested virtualization is enabled ($mod)" ;;
                *) die "nested virtualization is disabled in $mod (nested=$val).
  Enable it (with all VMs stopped):
    echo 'options $mod nested=1' | sudo tee /etc/modprobe.d/kvm-nested.conf
    sudo modprobe -r $mod && sudo modprobe $mod" ;;
            esac
        done
        [[ $found == yes ]] \
            || die "neither kvm_intel nor kvm_amd exposes a readable 'nested' parameter"
    fi

    virsh_ uri >/dev/null 2>&1 \
        || die "cannot connect to '$CONNECT' (is libvirtd running? are you in the libvirt group?)"

    local ver
    ver=$(virsh_ version 2>/dev/null | awk '/Using library/ {print $4}')
    if [[ -n $ver ]]; then
        [[ $(printf '%s\n' 7.2.0 "$ver" | sort -V | head -n1) == 7.2.0 ]] \
            || die "libvirt $ver is too old; need >= 7.2.0 for <firmware> feature selection"
    else
        warn "could not determine libvirt version; continuing"
    fi

    virsh_ pool-info "$POOL" >/dev/null 2>&1 \
        || die "storage pool '$POOL' not found (see: virsh pool-list --all)"
    [[ $(virsh_ pool-info "$POOL" | awk '/^State:/ {print $2}') == running ]] \
        || die "storage pool '$POOL' is not active (virsh pool-start $POOL)"

    virsh_ net-info "$NETWORK" >/dev/null 2>&1 \
        || die "libvirt network '$NETWORK' not found (see: virsh net-list --all)"
    [[ $(virsh_ net-info "$NETWORK" | awk '/^Active:/ {print $2}') == yes ]] \
        || die "libvirt network '$NETWORK' is not active (virsh net-start $NETWORK)"

    if virsh_ dominfo "$NAME" >/dev/null 2>&1; then
        die "a domain named '$NAME' already exists (virsh undefine $NAME --nvram --storage vda)"
    fi
    virsh_ vol-info --pool "$POOL" "$VOL" >/dev/null 2>&1 \
        && die "volume '$VOL' already exists in pool '$POOL'"
    return 0
}

# -------------------------------------------------------------------- XML --
build_xml() {
    local iso_x disk_x ioapic='' iommu='' usb='' video

    iso_x=$(xml_escape "$ISO")
    disk_x=$(xml_escape "$DISK_PATH")

    case $IOMMU in
        intel)
            # Interrupt remapping requires QEMU's split irqchip, which libvirt
            # selects via <ioapic driver='qemu'/>.
            ioapic="<ioapic driver='qemu'/>"
            iommu="<iommu model='intel'>
      <driver intremap='on' caching_mode='on' iotlb='on'/>
    </iommu>"
            ;;
        intel-basic)
            iommu="<iommu model='intel'/>"
            ;;
        none) ;;
    esac

    [[ $USB == yes ]] || usb="<controller type='usb' model='none'/>"

    case $VIDEO in
        vga) video="<model type='vga' vram='65536' heads='1' primary='yes'/>" ;;
        qxl) video="<model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>" ;;
    esac

    cat <<EOF
<domain type='kvm'>
  <name>$NAME</name>
  <description>Qubes OS dev/test guest (nested). Created by $PROG.</description>
  <memory unit='GiB'>$MEM_GIB</memory>
  <currentMemory unit='GiB'>$MEM_GIB</currentMemory>
  <vcpu placement='static'>$VCPUS</vcpu>
  <os firmware='efi'>
    <type arch='x86_64' machine='q35'>hvm</type>
    <firmware>
      <feature enabled='no' name='enrolled-keys'/>
      <feature enabled='no' name='secure-boot'/>
    </firmware>
  </os>
  <features>
    <acpi/>
    <apic/>
    $ioapic
  </features>
  <cpu mode='host-passthrough' check='none' migratable='off'>
    <topology sockets='1' cores='$VCPUS' threads='1'/>
  </cpu>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' discard='unmap'/>
      <source file='$disk_x'/>
      <target dev='vda' bus='virtio'/>
      <boot order='2'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$iso_x'/>
      <target dev='sda' bus='sata'/>
      <readonly/>
      <boot order='1'/>
    </disk>
    <interface type='network'>
      <source network='$NETWORK'/>
      <model type='$NIC_MODEL'/>
    </interface>
    <graphics type='spice' autoport='yes'>
      <listen type='address' address='127.0.0.1'/>
    </graphics>
    <video>
      $video
    </video>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <rng model='virtio'>
      <backend model='random'>/dev/urandom</backend>
    </rng>
    <serial type='pty'>
      <target type='isa-serial' port='0'>
        <model name='isa-serial'/>
      </target>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    $usb
    $iommu
    <memballoon model='none'/>
  </devices>
</domain>
EOF
}

# ------------------------------------------------------------------- main --
VOL="$NAME.qcow2"

if [[ $PRINT_XML == yes ]]; then
    # Offline mode: no libvirt calls, placeholder disk path.
    DISK_PATH=/var/lib/libvirt/images/$VOL
    build_xml
    exit 0
fi

check_host

log "creating ${DISK_GIB} GiB sparse qcow2 volume '$VOL' in pool '$POOL'"
virsh_ vol-create-as "$POOL" "$VOL" "${DISK_GIB}GiB" --format qcow2 >/dev/null
CREATED_VOL=yes
DISK_PATH=$(virsh_ vol-path --pool "$POOL" "$VOL")

TMP_XML=$(mktemp --suffix=.xml)
build_xml >"$TMP_XML"

log "defining domain '$NAME' ($VCPUS vCPUs, ${MEM_GIB} GiB RAM, iommu=$IOMMU)"
virsh_ define "$TMP_XML" >/dev/null
CREATED_VOL=no   # domain now references the volume; keep it from here on

virsh_ dominfo "$NAME"

if [[ $START == yes ]]; then
    log "starting '$NAME'"
    virsh_ start "$NAME"
fi

cat <<EOF

Done. Next steps:
  virsh -c $CONNECT start $NAME          # unless you passed --start
  virt-viewer -c $CONNECT $NAME          # or open it in virt-manager
  virsh -c $CONNECT console $NAME        # serial console (Xen/dom0 debugging)

Notes:
  - CD-ROM has boot priority; after installing, remove the ISO or boot from disk.
  - Secure Boot is off in the firmware selection. If the ISO still refuses to
    boot, check the OVMF setup menu.
  - If the installer reports missing IOMMU / interrupt remapping, or Xen fails
    to start with the full vIOMMU, retry with:  --iommu intel-basic
  - Passing an emulated NIC through to sys-net may need the no-strict-reset
    option on the PCI device attach (emulated devices lack FLR).

To remove the VM and its disk:
  virsh -c $CONNECT undefine $NAME --nvram --storage vda
EOF
