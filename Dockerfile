ARG FIVEM_NUM=17346
ARG FIVEM_VER=17346-c75a342e872e34d431322d03d45881f664a4098b
ARG DATA_VER=0e7ba538339f7c1c26d0e689aa750a336576cf02

ARG FEX_VER=FEX-2507.1

ARG DEBIAN_FRONTEND=noninteractive

FROM debian:bookworm-slim AS main

# --------------------------------------------------------------------------------

FROM main AS fex-builder-amd64

FROM --platform=arm64 main AS fex-builder-arm64

ARG DEBIAN_FRONTEND

ARG FEX_VER

RUN apt update && apt install -y cmake \
    clang-13 llvm-13 nasm ninja-build pkg-config \
    libcap-dev libglfw3-dev libepoxy-dev python3-dev libsdl2-dev \
    python3 linux-headers-generic  \
    git qtbase5-dev qtdeclarative5-dev lld \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /FEX
ADD https://github.com/FEX-Emu/FEX.git#${FEX_VER} ./

ARG CC=clang-13
ARG CXX=clang++-13
RUN mkdir build \
    && cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DUSE_LINKER=lld -DENABLE_LTO=True -DBUILD_TESTS=False -DENABLE_ASSERTIONS=False -G Ninja . \
    && ninja

WORKDIR /FEX/build

ARG TARGETARCH
FROM fex-builder-${TARGETARCH} AS fex-builder

# --------------------------------------------------------------------------------

FROM main AS fex-rootfs-amd64

FROM --platform=arm64 main AS fex-rootfs-arm64

ARG DEBIAN_FRONTEND

RUN apt-get update \
    && apt-get install -y jq curl squashfs-tools-ng \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root/.fex-emu/RootFS/Ubuntu_22_04
RUN curl -L https://rootfs.fex-emu.gg/RootFS_links.json -o /tmp/RootFS_links.json \
    && curl -L "$(jq -r '.v1 | ."Ubuntu 22.04 (SquashFS)" | .URL' /tmp/RootFS_links.json)" -o /tmp/ubuntu.sqsh \
    && sqfs2tar /tmp/ubuntu.sqsh | tar -x -p --numeric-owner -C ./

WORKDIR /root/.fex-emu

RUN echo '{"Config":{"RootFS":"Ubuntu_22_04"}}' > ./Config.json

ARG TARGETARCH
FROM fex-rootfs-${TARGETARCH} AS fex-rootfs

# --------------------------------------------------------------------------------

FROM main AS fx-downloader

ARG DEBIAN_FRONTEND

ARG FIVEM_VER
ARG DATA_VER

RUN apt update \
    && apt install -y wget xz-utils \
    && rm -rf /var/lib/apt/lists/* 

RUN mkdir -p /opt/cfx-server \
    && wget -O- https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${FIVEM_VER}/fx.tar.xz \
    | tar xJ --strip-components=0 -C /opt/cfx-server \
    && mkdir -p /opt/cfx-server-data \
    && wget -O- http://github.com/citizenfx/cfx-server-data/archive/${DATA_VER}.tar.gz \
    | tar xz --strip-components=1 -C /opt/cfx-server-data

ADD server.cfg /opt/cfx-server-data

# --------------------------------------------------------------------------------
FROM main AS base-amd64

FROM --platform=arm64 main AS base-arm64

ARG DEBIAN_FRONTEND

RUN apt update \
    && apt install -y \
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
    && rm -rf /var/lib/apt/lists/*

COPY --from=fex-builder /FEX/Bin/* /usr/bin/
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

RUN apt update \
    && apt install -y tini \
    && rm -rf /var/lib/apt/lists/*

COPY --from=fx-downloader /opt/cfx-server /opt/cfx-server
COPY --from=fx-downloader /opt/cfx-server-data /opt/cfx-server-data

RUN mkdir /txData \
    && ln -s /txData /opt/cfx-server/txData

ENV CFX_SERVER=/opt/cfx-server

ADD --chmod=755 entrypoint /usr/bin/entrypoint

WORKDIR /config
EXPOSE 30120

# Default to an empty CMD, so we can use it to add seperate args to the binary
CMD [""]

ENTRYPOINT ["tini", "--", "/usr/bin/entrypoint"]
STOPSIGNAL SIGKILL
