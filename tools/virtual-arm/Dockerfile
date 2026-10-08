FROM debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587

ENV LC_ALL=C DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture armel && dpkg --add-architecture armhf \
    && dpkg --add-architecture arm64 && apt-get update \
    && apt-get install --no-install-recommends -y \
       build-essential gcc-arm-linux-gnueabi gcc-arm-linux-gnueabihf \
       gcc-aarch64-linux-gnu libc6-dev-armel-cross libc6-dev-armhf-cross \
       libc6-dev-arm64-cross bc bison flex libssl-dev libelf-dev \
       cpio gzip xz-utils curl ca-certificates python3 jq patch \
       qemu-system-arm qemu-utils file coreutils \
    && mkdir -p /native-packages/armel /native-packages/armhf /native-packages/arm64 \
    && for arch in armel armhf arm64; do \
         cd "/native-packages/$arch"; \
         apt-get download \
           "libc6:$arch" "libgcc-s1:$arch" "jq:$arch" "libjq1:$arch" \
           "libonig5:$arch" "curl:$arch" "libcurl4:$arch" \
           "dnsmasq-base:$arch" "iproute2:$arch" "util-linux:$arch" \
           "coreutils:$arch" "gawk:$arch" "openssl:$arch" \
           "libssl3:$arch" "libnghttp2-14:$arch" "libidn2-0:$arch" \
           "librtmp1:$arch" "libssh2-1:$arch" "libpsl5:$arch" \
           "libgssapi-krb5-2:$arch" "libldap-2.5-0:$arch" \
           "libzstd1:$arch" "zlib1g:$arch" "libbrotli1:$arch" \
           "libkrb5-3:$arch" "libk5crypto3:$arch" "libcom-err2:$arch" \
           "libkrb5support0:$arch" "libkeyutils1:$arch" \
           "libunistring2:$arch" "libsasl2-2:$arch" \
           "libsasl2-modules-db:$arch" "libgnutls30:$arch" \
           "libhogweed6:$arch" "libnettle8:$arch" "libgmp10:$arch" \
           "libp11-kit0:$arch" "libtasn1-6:$arch" "libffi8:$arch" \
           "libreadline8:$arch" "libsigsegv2:$arch" "libtinfo6:$arch" \
           "libcap2:$arch" "libcap-ng0:$arch" "libbpf1:$arch" \
           "libelf1:$arch" "libmnl0:$arch" "libxtables12:$arch" \
           "libblkid1:$arch" "libmount1:$arch" "libsmartcols1:$arch" \
           "libuuid1:$arch" "libselinux1:$arch" "libpcre2-8-0:$arch" \
           "libdbus-1-3:$arch" "libsystemd0:$arch" "liblzma5:$arch" \
           "liblz4-1:$arch" "libgcrypt20:$arch" "libgpg-error0:$arch" \
           "libnetfilter-conntrack3:$arch" "libnfnetlink0:$arch" \
           "libnftables1:$arch" "libnftnl11:$arch" "libjansson4:$arch" \
           "libedit2:$arch" "libbsd0:$arch" "libmd0:$arch" \
           "libatomic1:$arch" "libmpfr6:$arch" "libdb5.3:$arch" \
           "libatm1:$arch" || exit 1; \
       done \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
