# Custom Image: Silverblue + Bazzite Kernel + Nvidia Open Drivers + ASUS Optimized
# Base Args
ARG BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-silverblue}"
ARG FEDORA_VERSION="${FEDORA_VERSION:-43}"
ARG ARCH="${ARCH:-x86_64}"

ARG BASE_IMAGE="${BASE_IMAGE:-ghcr.io/ublue-os/${BASE_IMAGE_NAME}-main:${FEDORA_VERSION}}"
ARG NVIDIA_BASE="${NVIDIA_BASE:-bazzite}"
ARG KERNEL_REF="${KERNEL_REF:-ghcr.io/bazzite-org/kernel-bazzite:latest-f${FEDORA_VERSION}-${ARCH}}"
ARG NVIDIA_REF="${NVIDIA_REF:-ghcr.io/bazzite-org/nvidia-drivers:latest-f${FEDORA_VERSION}-${ARCH}}"

# ----------------------------------------
# STAGE 1: Gather Artifacts
# ----------------------------------------
FROM ${KERNEL_REF} AS kernel
FROM ${NVIDIA_REF} AS nvidia

# Helper for build scripts
FROM scratch AS ctx
COPY build_files /

# ----------------------------------------
# STAGE 2: Main Build
# ----------------------------------------
FROM ${BASE_IMAGE} AS bazzfin 

ARG IMAGE_NAME="${IMAGE_NAME:-bazzfin}"
ARG IMAGE_VENDOR="${IMAGE_VENDOR:-ublue-os}"
ARG BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-silverblue}"

# Copy system files (Desktop Shared + Silverblue Specific + Nvidia Shared)
COPY system_files/desktop/shared system_files/desktop/${BASE_IMAGE_NAME} /
COPY system_files/nvidia/shared system_files/nvidia/${BASE_IMAGE_NAME} /
COPY firmware /

# Copy Homebrew from upstream
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /

# 1. CONFIGURE REPOS
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    mkdir -p /var/roothome && \
    dnf5 -y install dnf5-plugins && \
    for copr in \
        ublue-os/bazzite \
        ublue-os/bazzite-multilib \
        ublue-os/staging \
        ublue-os/packages \
        ublue-os/webapp-manager; \
    do \
        echo "Enabling copr: $copr"; \
        dnf5 -y copr enable $copr && \
        dnf5 -y config-manager setopt "copr:copr.fedorainfracloud.org:${copr////:}".priority=98 || true; \
    done && \
    unset -v copr && \
    dnf5 -y install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release{,-extras,-mesa} && \
    dnf5 -y install \
        https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
    if [ -f /etc/yum.repos.d/negativo17-fedora-multimedia.repo ]; then \
        sed -i 's@enabled=0@enabled=1@g' /etc/yum.repos.d/negativo17-fedora-multimedia.repo; \
    fi && \
    dnf5 -y config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-steam.repo && \
    dnf5 -y config-manager setopt "*bazzite*".priority=1 && \
    dnf5 -y config-manager setopt "*terra*".priority=3 "*terra*".exclude="nerd-fonts topgrade scx-tools scx-scheds steam python3-protobuf" && \
    dnf5 -y config-manager setopt "terra-mesa".enabled=true && \
    eval "$(/ctx/dnf5-setopt setopt '*negativo17*' priority=4 exclude='mesa-* *xone*')" && \
    dnf5 -y config-manager setopt "*rpmfusion*".priority=5 "*rpmfusion*".exclude="mesa-*" && \
    dnf5 -y config-manager setopt "*fedora*".exclude="mesa-* kernel-core-* kernel-modules-* kernel-uki-virt-*" && \
    dnf5 -y config-manager setopt "*staging*".exclude="scx-tools scx-scheds kf6-* mesa* mutter*" && \
    if dnf5 repolist --all 2>/dev/null | grep -q "linux-surface"; then \
        dnf5 -y config-manager setopt "linux-surface".enabled=false || true; \
    fi && \
    /ctx/cleanup

# 2. INSTALL BAZZITE KERNEL
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=kernel,src=/,dst=/rpms/kernel \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/install-kernel && \
    dnf5 -y config-manager setopt "*rpmfusion*".enabled=0 && \
    dnf5 -y copr enable bieszczaders/kernel-cachyos-addons && \
    dnf5 -y install \
        scx-scheds \
        scx-tools && \
    dnf5 -y copr disable bieszczaders/kernel-cachyos-addons && \
    declare -A toswap=( \
        ["copr:copr.fedorainfracloud.org:ublue-os:bazzite"]="plymouth" \
    ) && \
    for repo in "${!toswap[@]}"; do \
        for package in ${toswap[$repo]}; do \
            dnf5 -y swap --repo=$repo $package $package || true; \
        done; \
    done && \
    unset -v toswap repo package && \
    dnf5 versionlock add \
        plymouth \
        plymouth-scripts \
        plymouth-core-libs \
        plymouth-graphics-libs \
        plymouth-plugin-label \
        plymouth-plugin-two-step \
        plymouth-plugin-theme-spinner \
        plymouth-system-theme && \
    /ctx/cleanup

# 3. INSTALL STEAM DECK PATCHED PACKAGES (Core system components only)
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    dnf5 -y remove pipewire-config-raop || true && \
    declare -A toswap=( \
        ["copr:copr.fedorainfracloud.org:ublue-os:bazzite"]="wireplumber" \
        ["copr:copr.fedorainfracloud.org:ublue-os:bazzite-multilib"]="pipewire bluez xorg-x11-server-Xwayland" \
        ["terra-mesa"]="mesa-filesystem" \
        ["copr:copr.fedorainfracloud.org:ublue-os:staging"]="fwupd" \
    ) && \
    for repo in "${!toswap[@]}"; do \
        for package in ${toswap[$repo]}; do \
            dnf5 -y swap --repo=$repo $package $package || true; \
        done; \
    done && \
    unset -v toswap repo package && \
    dnf5 versionlock add \
        pipewire \
        pipewire-alsa \
        pipewire-gstreamer \
        pipewire-jack-audio-connection-kit \
        pipewire-jack-audio-connection-kit-libs \
        pipewire-libs \
        pipewire-plugin-libcamera \
        pipewire-pulseaudio \
        pipewire-utils \
        wireplumber \
        wireplumber-libs \
        bluez \
        bluez-cups \
        bluez-libs \
        bluez-obexd \
        xorg-x11-server-Xwayland \
        mesa-dri-drivers \
        mesa-filesystem \
        mesa-libEGL \
        mesa-libGL \
        mesa-libgbm \
        mesa-va-drivers \
        mesa-vulkan-drivers \
        fwupd \
        fwupd-plugin-uefi-capsule-data && \
    dnf5 -y install libfreeaptx && \
    dnf5 -y install --enable-repo="*rpmfusion*" --disable-repo="*fedora-multimedia*" \
        libaacs \
        libbdplus \
        libbluray \
        libbluray-utils && \
    /ctx/cleanup

# 4. INSTALL NVIDIA OPEN DRIVERS
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=bind,from=nvidia,src=/,dst=/rpms/nvidia \
    set -x && \
    echo "=== NVIDIA Driver Installation: Starting ===" && \
    dnf5 clean all && \
    dnf5 -y remove --noautoremove \
        NetworkManager-openvpn \
        NetworkManager-openvpn-gnome \
        openvpn || true && \
    rm -f /usr/lib/sysusers.d/nm-openvpn-sysusers.conf \
          /usr/lib/sysusers.d/openvpn.conf || true && \
    echo "=== Step 1: Removed conflicting NetworkManager packages ===" && \
    dnf5 -y remove --noautoremove \
        nvidia-gpu-firmware \
        rocm-hip \
        rocm-opencl \
        rocm-clinfo \
        rocm-smi || true && \
    echo "=== Step 2: Removed conflicting GPU packages ===" && \
    dnf5 -y copr enable ublue-os/staging && \
    echo "=== Step 3: Enabled staging repo ===" && \
    dnf5 -y install --best --allowerasing \
        egl-wayland.x86_64 \
        egl-wayland2.x86_64 && \
    echo "=== Step 4: Installed EGL Wayland packages ===" && \
    echo "=== Step 5: Running /ctx/install-nvidia ===" && \
    /ctx/install-nvidia && \
    echo "=== Step 6: NVIDIA drivers installed successfully ===" && \
    rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json && \
    ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so && \
    dnf5 -y copr disable ublue-os/staging && \
    echo "=== NVIDIA Driver Installation: Complete ===" && \
    /ctx/cleanup

# 5. CUSTOM PACKAGE CONFIGURATION (ASUS Optimized, No Gaming Bloat)
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=GITHUB_TOKEN \
    dnf5 -y remove --noautoremove \
        ublue-os-update-services \
        toolbox \
        htop \
        gamemode \
        gamescope \
        steam \
        lutris \
        ptyxis \
        gnome-software \
        gnome-classic-session \
        gnome-tour \
        gnome-extensions-app \
        gnome-system-monitor \
        gnome-initial-setup \
        gnome-shell-extension-background-logo \
        gnome-shell-extension-apps-menu \
        gnome-shell-extension-launch-new-instance \
        gnome-shell-extension-places-menu \
        gnome-shell-extension-window-list || true && \
    dnf5 -y install \
        libsecret \
        git-credential-libsecret \
        bazaar \
        iwd \
        greenboot \
        greenboot-default-health-checks \
        libadwaita \
        duperemove \
        cpulimit \
        sqlite \
        ryzenadj \
        ddcutil \
        input-remapper \
        libinput-utils \
        i2c-tools \
        lm_sensors \
        fw-ectool \
        webapp-manager \
        btop \
        duf \
        fish \
        lshw \
        wmctrl \
        p7zip \
        p7zip-plugins \
        rar \
        fastfetch \
        cockpit-networkmanager \
        cockpit-podman \
        cockpit-selinux \
        cockpit-system \
        cockpit-files \
        cockpit-storaged \
        topgrade \
        stress-ng \
        snapper \
        btrfs-assistant \
        edk2-ovmf \
        qemu \
        libvirt \
        lsb_release \
        uupd \
        ds-inhibit \
        nautilus-gsconnect \
        steamdeck-backgrounds \
        steamdeck-gnome-presets \
        gnome-randr-rust \
        gnome-shell-extension-user-theme \
        gnome-shell-extension-gsconnect \
        gnome-tweaks \
        rom-properties-gtk3 \
        openssh-askpass \
        firewall-config \
        asusctl \
        supergfxd || true && \
    dnf5 -y remove --setopt=clean_requirements_on_remove=1 '*i686' '*i386' || true && \
    systemctl mask iscsi || true && \
    if [ -f /usr/lib/systemd/system/uupd.service ]; then \
        sed -i 's|uupd|& --disable-module-distrobox|' /usr/lib/systemd/system/uupd.service; \
    fi && \
    systemctl enable dconf-update.service || true && \
    /ctx/cleanup

# 6. FINAL CLEANUP & OVERRIDES
COPY system_files/overrides /

RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    rm -f /etc/profile.d/toolbox.sh && \
    mkdir -p /var/tmp && chmod 1777 /var/tmp && \
    cp --no-dereference --preserve=links /usr/lib64/libdrm.so.2 /usr/lib64/libdrm.so || true && \
    echo "import \"/usr/share/ublue-os/just/80-bazzite.just\"" >> /usr/share/ublue-os/justfile && \
    echo "import \"/usr/share/ublue-os/just/81-bazzite-fixes.just\"" >> /usr/share/ublue-os/justfile && \
    echo "import \"/usr/share/ublue-os/just/95-bazzite-nvidia.just\"" >> /usr/share/ublue-os/justfile && \
    mkdir -p "/usr/share/ublue-os/dconfs/desktop-silverblue/" && \
    if ls /usr/share/glib-2.0/schemas/zz0-*-bazzite-desktop-silverblue-*.gschema.override 1> /dev/null 2>&1; then \
        cp /usr/share/glib-2.0/schemas/zz0-*-bazzite-desktop-silverblue-*.gschema.override "/usr/share/ublue-os/dconfs/desktop-silverblue/" && \
        find "/etc/dconf/db/distro.d/" -maxdepth 1 -type f -exec cp {} "/usr/share/ublue-os/dconfs/desktop-silverblue/" \; 2>/dev/null || true && \
        dconf-override-converter to-dconf "/usr/share/ublue-os/dconfs/desktop-silverblue/zz0-"*"-bazzite-desktop-silverblue-"*".gschema.override" && \
        rm "/usr/share/ublue-os/dconfs/desktop-silverblue/zz0-"*"-bazzite-desktop-silverblue-"*".gschema.override"; \
    fi && \
    mkdir -p "/usr/share/ublue-os/dconfs/nvidia-silverblue/" && \
    if ls /usr/share/glib-2.0/schemas/zz0-*-bazzite-nvidia-silverblue-*.gschema.override 1> /dev/null 2>&1; then \
        cp /usr/share/glib-2.0/schemas/zz0-*-bazzite-nvidia-silverblue-*.gschema.override "/usr/share/ublue-os/dconfs/nvidia-silverblue/" && \
        dconf-override-converter to-dconf "/usr/share/ublue-os/dconfs/nvidia-silverblue/zz0-"*"-bazzite-nvidia-silverblue-"*".gschema.override" && \
        rm "/usr/share/ublue-os/dconfs/nvidia-silverblue/zz0-"*"-bazzite-nvidia-silverblue-"*".gschema.override"; \
    fi && \
    mkdir -p /tmp/bazzite-schema-test && \
    find "/usr/share/glib-2.0/schemas/" -type f ! -name "*.gschema.override" -exec cp {} "/tmp/bazzite-schema-test/" \; && \
    if ls /usr/share/glib-2.0/schemas/zz0-*.gschema.override 1> /dev/null 2>&1; then \
        cp /usr/share/glib-2.0/schemas/zz0-*.gschema.override "/tmp/bazzite-schema-test/"; \
    fi && \
    glib-compile-schemas --strict /tmp/bazzite-schema-test && \
    glib-compile-schemas /usr/share/glib-2.0/schemas &>/dev/null || true && \
    rm -rf /tmp/bazzite-schema-test && \
    for repo in fedora-cisco-openh264 fedora-steam fedora-rar google-chrome _copr_ublue-os-akmods terra terra-extras negativo17-fedora-multimedia; do \
        if [ -f "/etc/yum.repos.d/$repo.repo" ]; then \
            sed -i 's@enabled=1@enabled=0@g' "/etc/yum.repos.d/$repo.repo"; \
        fi; \
    done && \
    for copr in \
        ublue-os/bazzite \
        ublue-os/bazzite-multilib \
        ublue-os/staging \
        ublue-os/packages \
        ublue-os/webapp-manager; \
    do \
        dnf5 -y copr disable $copr || true; \
    done && \
    if [ -f /etc/tuned/ppd.conf ]; then \
        sed -i 's/power-saver=powersave$/power-saver=powersave-bazzite/' /etc/tuned/ppd.conf && \
        sed -i 's/balanced=balanced$/balanced=balanced-bazzite/' /etc/tuned/ppd.conf && \
        sed -i 's/performance=throughput-performance$/performance=throughput-performance-bazzite/' /etc/tuned/ppd.conf; \
    fi && \
    systemctl disable scx_loader.service || true && \
    systemctl enable input-remapper.service || true && \
    systemctl disable rpm-ostreed-automatic.timer || true && \
    systemctl enable uupd.timer || true && \
    systemctl enable incus-workaround.service || true && \
    systemctl enable bazzite-hardware-setup.service || true && \
    systemctl enable ds-inhibit.service || true && \
    systemctl --global enable bazzite-user-setup.service || true && \
    systemctl enable greenboot-healthcheck.service || true && \
    systemctl disable supergfxd.service || true && \
    dnf5 config-manager setopt skip_if_unavailable=1 && \
    /ctx/image-info && \
    /ctx/build-initramfs && \
    /ctx/finalize

RUN bootc container lint
