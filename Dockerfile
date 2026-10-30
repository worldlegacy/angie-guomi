# ============================================================
# Dockerfile: 编译 Angie + Tongsuo 国密版（产出离线包）
# 用法：
#   1. docker build -t angie-guomi-build .
#   2. docker run --rm -v $(pwd)/output:/out angie-guomi-build
#   3. ls output/  -> angie-guomi-offline.tar.gz
# 或者直接在任何有 Docker 的 Linux 机器上跑
# ============================================================

FROM ubuntu:22.04 AS builder

ARG ANGIE_VERSION=1.12.4
ARG TONGSUO_VERSION=8.5.0
ARG PREFIX=/usr/local/angie

# ------------------------------------------------------------
# 安装编译依赖
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc g++ make \
    libpcre3 libpcre3-dev \
    zlib1g-dev \
    perl \
    wget curl tar ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# ------------------------------------------------------------
# 下载源码
# ------------------------------------------------------------
RUN wget -c -O angie.tar.gz \
      "https://github.com/webserver-llc/angie/archive/refs/tags/Angie-${ANGIE_VERSION}.tar.gz" \
 && wget -c -O tongsuo.tar.gz \
      "https://github.com/Tongsuo-Project/Tongsuo/archive/refs/tags/${TONGSUO_VERSION}.tar.gz" \
 && tar -xzf angie.tar.gz \
 && tar -xzf tongsuo.tar.gz \
 && rm angie.tar.gz tongsuo.tar.gz

# ------------------------------------------------------------
# 编译安装（链接 Tongsuo 国密）
# ------------------------------------------------------------
RUN ANGIE_SRC=$(ls -d angie*/ | head -1 | tr -d '/') && \
    TONGSUO_SRC=$(ls -d Tongsuo*/ | head -1 | tr -d '/') && \
    echo "Angie: ${ANGIE_SRC}, Tongsuo: ${TONGSUO_SRC}" && \
    cd "${ANGIE_SRC}" && \
    ./configure \
        --prefix="${PREFIX}" \
        --with-openssl="../${TONGSUO_SRC}" \
        --with-openssl-opt="enable-ntls" \
        --with-ntls \
        --with-http_ssl_module \
        --with-stream_ssl_module \
        --with-http_v2_module \
        --with-http_stub_status_module \
        --with-http_realip_module \
        --with-pcre \
        --with-zlib \
        --with-compat && \
    make -j$(nproc) && \
    make install

# ------------------------------------------------------------
# 打包离线包
# ------------------------------------------------------------
RUN OUTPUT_DIR=angie-offline-package && \
    mkdir -p "${OUTPUT_DIR}" && \
    cp -a "${PREFIX}" "${OUTPUT_DIR}/angie" && \
    echo "" && \
    echo "编译完成！二进制类型：" && \
    file "${OUTPUT_DIR}/angie/sbin/angie" && \
    "${OUTPUT_DIR}/angie/sbin/angie" -v && \
    tar -czf /out/angie-guomi-offline.tar.gz "${OUTPUT_DIR}" || true


# ============================================================
# 最终镜像（如果想直接跑 Angie 国密版）
# ============================================================
FROM ubuntu:22.04 AS runtime

RUN apt-get update && apt-get install -y \
    libpcre3 zlib1g ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/angie /usr/local/angie

EXPOSE 443
EXPOSE 80

CMD ["/usr/local/angie/sbin/angie", "-g", "daemon off;"]
