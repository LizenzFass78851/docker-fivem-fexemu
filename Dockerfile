ARG FIVEM_NUM=35636
ARG FIVEM_VER=35636-337a77d62259709e6817b3bcbfff0cdb54930c85
ARG DATA_VER=32d98e7524b952faf8b220d719615b0346b0a6cc

ARG FEX_VER=FEX-2608
ARG FEX_INSTALL_PATH=/opt/fex-emu

ARG DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------------------------------------
# --------------------------------------------------------------------------------

FROM ubuntu:26.04 AS stage

ARG DEBIAN_FRONTEND
WORKDIR /etc/apt/mirrors
RUN cat > /etc/apt/mirrors/ubuntu.list <<'EOF'
http://azure.archive.ubuntu.com/ubuntu	priority:1
http://archive.ubuntu.com/ubuntu	priority:2
http://mirrors.dotsrc.org/ubuntu	priority:3
EOF
RUN cat > /etc/apt/mirrors/ubuntu-ports.list <<'EOF'
http://azure.ports.ubuntu.com/ubuntu-ports	priority:1
http://ports.ubuntu.com/ubuntu-ports	priority:2
http://mirrors.dotsrc.org/ubuntu-ports	priority:3
EOF
RUN (sed -E -i 's#http://[^[:space:]]*ubuntu\.com/ubuntu-ports#mirror+file:///etc/apt/mirrors/ubuntu-ports.list#g' /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources || true) \
&&  (sed -E -i 's#http://[^[:space:]]*ubuntu\.com/ubuntu#mirror+file:///etc/apt/mirrors/ubuntu.list#g'             /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources || true)
RUN if ls --version | grep -q uutils; then \
    apt-get update > /dev/null && apt-get remove -y --allow-remove-essential coreutils-from-uutils; \ 
    rm -rf /var/cache/apt /var/lib/apt/lists; else \
    echo "uutils coreutils not found, skipping removal."; fi

# --------------------------------------------------------------------------------

FROM ubuntu:22.04 AS build

ARG DEBIAN_FRONTEND
WORKDIR /etc/apt/mirrors
RUN cat > /etc/apt/mirrors/ubuntu.list <<'EOF'
http://azure.archive.ubuntu.com/ubuntu	priority:1
http://archive.ubuntu.com/ubuntu	priority:2
http://mirrors.dotsrc.org/ubuntu	priority:3
EOF
RUN cat > /etc/apt/mirrors/ubuntu-ports.list <<'EOF'
http://azure.ports.ubuntu.com/ubuntu-ports	priority:1
http://ports.ubuntu.com/ubuntu-ports	priority:2
http://mirrors.dotsrc.org/ubuntu-ports	priority:3
EOF
RUN (sed -E -i 's#http://[^[:space:]]*ubuntu\.com/ubuntu-ports#mirror+file:///etc/apt/mirrors/ubuntu-ports.list#g' /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources || true) \
&&  (sed -E -i 's#http://[^[:space:]]*ubuntu\.com/ubuntu#mirror+file:///etc/apt/mirrors/ubuntu.list#g'             /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources || true)
RUN if ls --version | grep -q uutils; then \
    apt-get update > /dev/null && apt-get remove -y --allow-remove-essential coreutils-from-uutils; \ 
    rm -rf /var/cache/apt /var/lib/apt/lists; else \
    echo "uutils coreutils not found, skipping removal."; fi

# --------------------------------------------------------------------------------
# --------------------------------------------------------------------------------

FROM build AS fex-builder-amd64

FROM --platform=arm64 build AS fex-builder-arm64

ARG DEBIAN_FRONTEND

ARG FEX_VER
ARG FEX_INSTALL_PATH

RUN apt-get update && apt-get install -y cmake \
        clang-13 llvm-13 nasm ninja-build pkg-config \
        libcap-dev libglfw3-dev libepoxy-dev python3-dev libsdl2-dev \
        python3 linux-headers-generic  \
        git qtbase5-dev qtdeclarative5-dev lld \
        && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /FEX
ADD https://github.com/FEX-Emu/FEX.git#${FEX_VER} ./

ARG CC=clang-13
ARG CXX=clang++-13
RUN for ARCH in v80 v82 v84; do \
        BUILD_DIR="/FEX/build/$ARCH"; \
        mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"; \
        case $ARCH in \
            v80) MARCH="armv8-a"; PKG="fex-emu-armv8.0" ;; \
            v82) MARCH="armv8.2-a"; PKG="fex-emu-armv8.2" ;; \
            v84) MARCH="armv8.4-a"; PKG="fex-emu-armv8.4" ;; \
        esac; \
        cmake \
            -DCMAKE_INSTALL_PREFIX=/usr \
            -DCMAKE_BUILD_TYPE=Release \
            -DUSE_LINKER=lld \
            -DENABLE_LTO=True \
            -DBUILD_TESTING=False \
            -DENABLE_ASSERTIONS=False \
            -DTUNE_CPU=generic \
            -DTUNE_ARCH=$MARCH \
            -G Ninja \
            ../../ \
        && ninja && DESTDIR="$FEX_INSTALL_PATH/$PKG" ninja install \
        && mkdir "$FEX_INSTALL_PATH/$PKG/bin" "$FEX_INSTALL_PATH/$PKG/lib" \
        && mv $FEX_INSTALL_PATH/$PKG/usr/bin/* $FEX_INSTALL_PATH/$PKG/bin/ \
        && mv $FEX_INSTALL_PATH/$PKG/usr/lib/* $FEX_INSTALL_PATH/$PKG/lib/ \
        && rm -rf "$FEX_INSTALL_PATH/$PKG/usr"; \
    done

WORKDIR ${FEX_INSTALL_PATH}

ARG TARGETARCH
FROM fex-builder-${TARGETARCH} AS fex-builder

# --------------------------------------------------------------------------------

FROM stage AS fex-rootfs-amd64

FROM --platform=arm64 stage AS fex-rootfs-arm64

ARG DEBIAN_FRONTEND

RUN apt-get update \
    && apt-get install -y jq curl squashfs-tools-ng \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /root/.fex-emu/RootFS/ArchLinux
ADD https://rootfs.fex-emu.gg/RootFS_links.json /tmp/RootFS_links.json
RUN curl -L "$(jq -r '.v1 | ."ArchLinux (SquashFS)" | .URL' /tmp/RootFS_links.json)" -o /tmp/rootfs.sqsh \
    && sqfs2tar /tmp/rootfs.sqsh | tar -x -p --numeric-owner -C ./

WORKDIR /root/.fex-emu

RUN echo '{"Config":{"RootFS":"ArchLinux"}}' > ./Config.json

ARG TARGETARCH
FROM fex-rootfs-${TARGETARCH} AS fex-rootfs

# --------------------------------------------------------------------------------

FROM stage AS fx-downloader

ARG DEBIAN_FRONTEND

ARG FIVEM_VER
ARG DATA_VER

RUN apt-get update \
    && apt-get install -y wget xz-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/cfx-server
ADD https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${FIVEM_VER}/fx.tar.xz /tmp/fx.tar.xz
RUN tar xJ --strip-components=0 -C /opt/cfx-server -f /tmp/fx.tar.xz
WORKDIR /opt/cfx-server-data
ADD http://github.com/citizenfx/cfx-server-data/archive/${DATA_VER}.tar.gz /tmp/cfx-server-data.tar.gz
RUN tar xz --strip-components=1 -C /opt/cfx-server-data -f /tmp/cfx-server-data.tar.gz

ADD server.cfg /opt/cfx-server-data

# --------------------------------------------------------------------------------
FROM stage AS base-amd64

FROM --platform=arm64 stage AS base-arm64

ARG DEBIAN_FRONTEND
ARG FEX_INSTALL_PATH
ENV FEX_INSTALL_PATH=${FEX_INSTALL_PATH}

RUN apt-get update \
    && apt-get install -y \
    curl \
    squashfuse \
    fuse3 \
    squashfs-tools \
    zenity \
    qml-module-qtquick-controls \
    qml-module-qtquick-controls2 \
    qml-module-qtquick-dialogs \
    libc6 \
    libgcc-s1 \
    libgl1 \
    libqt5core5a \
    libqt5gui5-gles \
    libqt5qml5 \
    libqt5quick5-gles \
    libqt5widgets5 \
    libstdc++6 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=fex-builder ${FEX_INSTALL_PATH} ${FEX_INSTALL_PATH}
COPY --from=fex-rootfs /root/.fex-emu /root/.fex-emu

ARG TARGETARCH
FROM base-${TARGETARCH}

ARG DEBIAN_FRONTEND

ARG FIVEM_VER
ARG FIVEM_NUM
ARG DATA_VER

LABEL org.opencontainers.image.authors="" \
      org.opencontainers.image.vendor="LizenzFass78851" \
      org.opencontainers.image.title="FiveM" \
      org.opencontainers.image.url="https://fivem.net" \
      org.opencontainers.image.description="FiveM is a modification for Grand Theft Auto V enabling you to play multiplayer on customized dedicated servers." \
      org.opencontainers.image.version=${FIVEM_NUM} \
      io.spritsail.version.fivem=${FIVEM_VER} \
      io.spritsail.version.fivem_data=${DATA_VER}

RUN apt-get update \
    && apt-get install -y tini \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=fx-downloader /opt/cfx-server /opt/cfx-server
COPY --from=fx-downloader /opt/cfx-server-data /opt/cfx-server-data

RUN mkdir /txData \
    && ln -s /txData /opt/cfx-server/txData

ENV CFX_SERVER=/opt/cfx-server

ADD --chmod=755 entrypoint /usr/bin/entrypoint
ADD --chmod=755 fex-starter.sh /usr/local/bin/fex-starter.sh

WORKDIR /config
EXPOSE 30120

# Default to an empty CMD, so we can use it to add seperate args to the binary
CMD [""]

ENTRYPOINT ["tini", "--", "/usr/bin/entrypoint"]
STOPSIGNAL SIGKILL
