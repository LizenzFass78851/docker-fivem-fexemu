ARG FIVEM_NUM=14758
ARG FIVEM_VER=14758-36b17e986ff6393de11928a14d485c8ed053c194
ARG DATA_VER=0e7ba538339f7c1c26d0e689aa750a336576cf02

ARG FEX_VER=FEX-2504

ARG DEBIAN_FRONTEND=noninteractive

FROM --platform=arm64 ubuntu:24.04 AS fex-builder

ARG DEBIAN_FRONTEND

ARG FEX_VER

RUN apt update && apt install -y cmake \
    clang-13 llvm-13 nasm ninja-build pkg-config \
    libcap-dev libglfw3-dev libepoxy-dev python3-dev libsdl2-dev \
    python3 linux-headers-generic  \
    git qtbase5-dev qtdeclarative5-dev lld \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /FEX
RUN git clone \
    --recurse-submodules \
    https://github.com/FEX-Emu/FEX.git \
    -b ${FEX_VER} \
    --depth 1 \
    . && \
    mkdir build

ARG CC=clang-13
ARG CXX=clang++-13
RUN cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DUSE_LINKER=lld -DENABLE_LTO=True -DBUILD_TESTS=False -DENABLE_ASSERTIONS=False -G Ninja .
RUN ninja

WORKDIR /FEX/build

FROM ubuntu:24.04 AS fx-downloader

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

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND

ARG FIVEM_VER
ARG FIVEM_NUM
ARG DATA_VER

LABEL maintainer="" \
      org.label-schema.vendor="LizenzFass78851" \
      org.label-schema.name="FiveM" \
      org.label-schema.url="https://fivem.net" \
      org.label-schema.description="FiveM is a modification for Grand Theft Auto V enabling you to play multiplayer on customized dedicated servers." \
      org.label-schema.version=${FIVEM_NUM} \
      io.spritsail.version.fivem=${FIVEM_VER} \
      io.spritsail.version.fivem_data=${DATA_VER}

RUN apt update \
    && apt install -y tini \
    libcap-dev libglfw3-dev libepoxy-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=fex-builder /FEX/Bin/* /usr/bin/

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
