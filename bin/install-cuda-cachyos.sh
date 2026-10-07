#!/bin/bash

# ----------------------------------------------------------------------
# Full system setup script for a CUDA‑capable server.
#
# This script installs the required NVIDIA CUDA libraries and tools for
# llama‑server, disables desktop‑friendly services (plymouth, quiet splash),
# configures the kernel command line (zram, zswap, nomodset), creates a
# 128 GiB swapfile on btrfs, ensures the latest NVIDIA modules are active,
# removes unneeded desktop packages, and updates the bootloader.
# ----------------------------------------------------------------------

# Safe bash
set -e                   # exit on any error
set -u                   # unset variable is an error
set -o pipefail          # pipeline fails if any component fails
set -o noclobber         # defensive: prevent accidental file overwrite via > redirection
shopt -s inherit_errexit # propagate `set -e` to command substitutions (not `set -u` or `pipefail`)

sudo=${sudo-sudo}
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Provide functions: config_rm, config_add and cleanup_backups
source "$dir/config.sh"

# https://wiki.cachyos.org/features/kernel
# linux-cachyos-server
# Tuned for server workloads compared to desktop usage.
# - 300Hz tickrate
# - No preemption
# - Scheduler EEVDF https://github.com/CachyOS/linux-cachyos#available-schedulers
#
# linux-cachyos-server      GCC
# linux-cachyos-server-lto  Clang + ThinLTO
# linux-cachyos             Clang + ThinLTO + AutoFDO

(
    # Print command lines
    set -x

    # Install required packages for llama.cpp on a server
    $sudo pacman -Syu --noconfirm --needed   \
                                             \
        btrfs-progs                          \
        limine                               \
        linux-cachyos-server-lto-nvidia-open \
                                             \
        blas-openblas                        \
        cuda                                 \
        cudnn                                \
        nccl                                 \
        nvidia-container-toolkit             \
        nvidia-utils                         \
        nvtop                                \
                                             \
        ccache                               \
        cmake                                \
        gcc                                  \
        git                                  \
        make                                 \
        ninja                                \
                                             \
        gawk                                 \
        go                                   \
        jq                                   \
        npm                                  \
        perl                                 \
        sed                                  \
                                             \
        coreutils                            \
        ripgrep                              \
        tmux                                 \
        tree                                 \
        wget                                 \
                                             \
        bash                                 \
        zsh                                  \
                                             \
        btop                                 \
        htop                                 \
                                             \
        nano                                 \
        neovim                               \
        neovim-lspconfig                     \
        vim                                  \

)

# Disable some Desktop-friendly settings that are annoying for a server
config_rm   HOOKS          plymouth                    /etc/mkinitcpio.conf
config_rm   KERNEL_CMDLINE quiet                       /etc/default/limine
config_rm   KERNEL_CMDLINE splash                      /etc/default/limine
config_add  KERNEL_CMDLINE nomodset                    /etc/default/limine
config_add  KERNEL_CMDLINE systemd.zram=0              /etc/default/limine
config_add  KERNEL_CMDLINE zswap.enabled=1             /etc/default/limine
config_add  KERNEL_CMDLINE zswap.shrinker_enabled=1    /etc/default/limine
config_add  KERNEL_CMDLINE zswap.compressor=lz4        /etc/default/limine
config_add  KERNEL_CMDLINE zswap.max_pool_percent=5    /etc/default/limine

# Clean up old backups in both /etc and /etc/default
cleanup_backups /etc
cleanup_backups /etc/default

(
    if [[ ! -e /swapfile ]]; then
        set -x
        $sudo swapoff -a
        $sudo btrfs filesystem mkswapfile --size 128G /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
        $sudo swapon -a
    else
        # Print command lines
        set -x
    fi

    # Ensure latest Nvidia modules
    $sudo chwd -i nvidia-open-dkms || true
)

# Remove Desktop-related packages
# TODO also remove: plymouth cachyos-packageinstaller
for pkg in                              \
    accountsservice                     \
    adwaita-fonts                       \
    adwaita-icon-theme-                 \
    alsa-firmware                       \
    alsa-plugins                        \
    alsa-utils                          \
    ananicy-cpp                         \
    at-spi2-core                        \
    awesome-terminal-fonts              \
    bluez-hid2hci                       \
    bluez-utils                         \
    bpftune-git                         \
    btrfs-assistant                     \
    cachyos-ananicy-rules               \
    cachyos-kernel-manager              \
    cachyos-plymouth-bootanimation      \
    cachyos-plymouth-theme              \
    cachyos-wallpapers                  \
    cantarell-fonts                     \
    cmfy-bin                            \
    default-cursors                     \
    desktop-file-utils                  \
    dosfstools                          \
    exfatprogs                          \
    f2fs-tools                          \
    gsettings-desktop-schemas           \
    gsettings-system-schemas            \
    gst-plugins-bad-libs                \
    gst-plugins-base-libs               \
    gstreamer                           \
    gtk-update-icon-cache               \
    gtk3                                \
    gtk4                                \
    hicolor-icon-theme                  \
    iw                                  \
    lib32-curl                          \
    lib32-expat                         \
    lib32-json-c                        \
    lib32-libdrm                        \
    lib32-libglvnd                      \
    lib32-libxml2                       \
    lib32-libxxf86vm                    \
    lib32-mesa                          \
    lib32-ncurses                       \
    lib32-nvidia-utils                  \
    lib32-opencl-nvidia                 \
    lib32-vulkan-icd-loader             \
    lib32-wayland                       \
    lib32-xz                            \
    libcolord                           \
    libcups                             \
    libdecor                            \
    libepoxy                            \
    libglvnd                            \
    libinput                            \
    libva                               \
    libva-nvidia-driver                 \
    libxcomposite                       \
    libxcursor                          \
    libxdamage                          \
    libxinerama                         \
    libxnvctrl                          \
    libxrandr                           \
    libxtst                             \
    libxv                               \
    linux-cachyos                       \
    linux-cachyos-headers               \
    linux-cachyos-lts                   \
    linux-cachyos-lts-headers           \
    linux-cachyos-lts-nvidia-open       \
    linux-cachyos-nvidia-open           \
    linux-cachyos-server                \
    linux-firmware-radeon               \
    mesa                                \
    mesa-utils                          \
    noto-color-emoji-fontconfig         \
    noto-fonts                          \
    nvidia-cg-toolkit                   \
    nvidia-settings                     \
    nvidia-utils                        \
    octopi                              \
    qt6-base                            \
    qt6-base                            \
    qt6-svg                             \
    qt6-translations                    \
    qt6-wayland                         \
    shelly                              \
    spdlog                              \
    terminology                         \
    ttf-bitstream-vera                  \
    ttf-dejavu                          \
    ttf-liberation                      \
    ttf-opensans                        \
    unrar                               \
    unrar                               \
    vmaf                                \
    vulkan-icd-loader                   \
    wayland                             \
    wireless-regdb                      \
    xf86-input-libinput                 \
    xorg-xprop                          \

do
    pacman -Qtq | rg -sq "^$pkg\$" &&
        (
            set -x # Print command lines
            $sudo pacman -Rcsun "$pkg" || :
        )
done

(
    # Print command line
    set -x

    # Update bootloader config
    $sudo limine-update
)

echo "
Please verify the packages, settings and /etc/default/limine

After, you may want to reboot:

    $sudo reboot
"
