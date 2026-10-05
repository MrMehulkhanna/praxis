# shellcheck shell=bash
# Praxis hardware detection — sourced by praxis-install and by the test suite.
# Every function takes its input as arguments (never reads the machine
# directly), so behaviour can be tested with recorded fixtures.

# praxis_ucode <cpu vendor_id> → microcode package, or nothing
praxis_ucode() {
    case "$1" in
        GenuineIntel) echo "intel-ucode" ;;
        AuthenticAMD) echo "amd-ucode" ;;
    esac
}

# praxis_gpu_pkgs <output of `lspci -nn`> → space-separated driver packages
#
# Matches on PCI vendor IDs, not names: a pattern like "ati" also matches
# "Corporation", which would pull AMD drivers onto every Intel/NVIDIA box.
#   8086 Intel · 1002 AMD/ATI · 10de NVIDIA
# NVIDIA's open kernel modules require Turing or newer (device id ≥ 0x1e00);
# older NVIDIA GPUs get the open-source nouveau/NVK stack instead.
praxis_gpu_pkgs() {
    local gpus pkgs=() id nv_new=0 nv_old=0
    gpus=$(grep -iE 'vga|3d controller|display controller' <<<"$1" || true)

    grep -qiE '\[8086:[0-9a-f]{4}\]' <<<"$gpus" && pkgs+=(mesa vulkan-intel intel-media-driver)
    grep -qiE '\[1002:[0-9a-f]{4}\]' <<<"$gpus" && pkgs+=(mesa vulkan-radeon xf86-video-amdgpu)

    # (no NVIDIA GPU is the normal case: grep finding nothing must not count as a
    # failure for a caller running under `set -eE` with an ERR trap — the
    # installer's trap would otherwise fire inside this command substitution)
    for id in $(grep -oiE '\[10de:[0-9a-f]{4}\]' <<<"$gpus" | cut -d: -f2 | tr -d ']' || true); do
        [[ "$id" =~ ^[0-9a-fA-F]{4}$ ]] || continue
        if (( 16#$id >= 16#1e00 )); then nv_new=1; else nv_old=1; fi
    done

    if [ "$nv_new" = 1 ]; then
        pkgs+=(nvidia-open nvidia-utils)
    elif [ "$nv_old" = 1 ]; then
        pkgs+=(mesa vulkan-nouveau)
    fi

    [ "${#pkgs[@]}" -eq 0 ] && pkgs=(mesa)
    printf '%s\n' "${pkgs[@]}" | awk '!seen[$0]++' | paste -sd' ' -
}

# praxis_largest_free <output of `parted -sm DISK unit MiB print free`> [min_mib]
#   → "START END SIZE_MIB" of the largest free region ≥ min_mib (default 30 GiB)
praxis_largest_free() {
    awk -F: -v min="${2:-30720}" '
        /:free;$/ { sz = $4; gsub("MiB", "", sz); if (sz + 0 > max) { max = sz + 0; s = $2; e = $3 } }
        END       { if (max >= min) printf "%s %s %d\n", s, e, max }' <<<"$1"
}
