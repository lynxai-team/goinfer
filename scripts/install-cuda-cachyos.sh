#!/bin/bash

# Safe bash
set -e                   # stop the script if any command returns a non‑zero status
set -u                   # unset variable is an error => exit
set -o pipefail          # pipeline fails if any of its components fails
set -o noclobber         # prevent accidental file overwriting with > redirection
shopt -s inherit_errexit # apply these restrictions to $(command substitution)

# Install the required Nvidia CUDA libs and tools for llama-server
# https://github.com/ggml-org/llama.cpp/tree/master/tools/server

# If you are already root, set empty sudo variable: export sudo=""
sudo=${sudo-sudo}

# https://wiki.cachyos.org/features/kernel
# linux-cachyos-server
# Tuned for server workloads compared to desktop usage.
# - 300Hz tickrate
# - No preemption
# - Stock EEVDF
# linux-cachyos-server         GCC
# linux-cachyos-hardened-lto   Clang + ThinLTO + AutoFDO https://github.com/CachyOS/cachyos-benchmarker/blob/master/kernel-autofdo.sh

(
    # Print command lines
    set -x

    # Install required packages for llama.cpp on a server
    $sudo pacman -Syu --noconfirm            \
                                             \
        linux-cachyos-server-lto-nvidia-open \
                                             \
        cuda                                 \
        cudnn                                \
        nccl                                 \
        nvidia-container-toolkit             \
        nvidia-utils                         \
        nvtop                                \
                                             \
        ccache                               \
        cmake                                \
        git                                  \
        go                                   \
        ninja                                \
        npm                                  \
                                             \
        btop                                 \
        htop                                 \
        screen                               \
        tree                                 \
        wget                                 \

)

# Remove Desktop-related packages
for pkg in                              \
    adwaita-fonts                       \
    adwaita-icon-theme-                 \
    at-spi2-core                        \
    btrfs-assistant                     \
    cachyos-plymouth-bootanimation      \
    cachyos-plymouth-theme              \
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
    lib32-libdrm                        \
    lib32-libglvnd                      \
    lib32-libxxf86vm                    \
    lib32-mesa                          \
    lib32-nvidia-utils                  \
    lib32-opencl-nvidia                 \
    lib32-vulkan-icd-loader             \
    lib32-wayland                       \
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
    nvidia-cg-toolkit                   \
    nvidia-settings                     \
    nvidia-utils                        \
    plymouth                            \
    qt6-base                            \
    qt6-svg                             \
    qt6-translations                    \
    shelly                              \
    vmaf                                \
    vulkan-icd-loader                   \
    wayland                             \
    xorg-xprop                          \
    ananicy-cpp                         \
    cachyos-settings                    \
    inxi                                \
    iw                                  \
    spdlog                              \
    wireless-regdb                      \
    zram-generator                      \
    cachyos-ananicy-rules               \
    ;
do
    pacman -Qtq | rg -sq "^$pkg\$" &&
        (
            set -x # Print command lines
            $sudo pacman -Rcsun "$pkg"
        )
done

(
    if [[ ! -e /swapfile ]] 
    then
        set -x
        sudo swapoff -a
        sudo btrfs filesystem mkswapfile --size 128G /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
        sudo swapon -a
    fi

    # Print command lines
    set -x

    # Ensure latest Nvidia modules
    $sudo sudo chwd -i nvidia-open-dkms || true

    # Disable zram, enable zswap
    $sudo sed 's/KERNEL_CMDLINE.* rw /KERNEL_CMDLINE[default]+="systemd.zram=0 zswap.enabled=1 zswap.shrinker_enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=5 nomodset nowatchdog rw /' /etc/default/limine --in-place=.backup

    # Update bootloader config
    $sudo limine-update
)

echo "
Please verify the packages, settings and /etc/default/limine

After, you may want to reboot:

    $sudo reboot
"
