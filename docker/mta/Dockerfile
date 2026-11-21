# Servidor MTA:SA 1.6 para Linux (x64 o arm64 segun la maquina).
# Los recursos del repo NO se copian a la imagen: docker-compose los monta como volumen.

# --- Etapa 1: descargas ---
FROM debian:bookworm-slim AS download
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# TARGETARCH lo rellena Docker (amd64 o arm64): en un Mac con Apple Silicon se usa el
# binario arm64 nativo del servidor, sin emulacion.
ARG TARGETARCH
ARG LIBSSL11_VERSION=1.1.1w-0+deb11u1
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
        amd64) pkg=multitheftauto_linux_x64;   bin=mta-server64 ;; \
        arm64) pkg=multitheftauto_linux_arm64; bin=mta-server-arm64 ;; \
        *) echo "Arquitectura no soportada: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL "https://linux.multitheftauto.com/dl/${pkg}.tar.gz" | tar xz -C /tmp; \
    mv "/tmp/${pkg}" /opt/mta; \
    ln -s "/opt/mta/${bin}" /opt/mta/mta-server; \
    mkdir -p /opt/mta/mods/deathmatch/resources /opt/mta/mods/deathmatch/logs; \
    # dbconmy.so (modulo MySQL del servidor) esta enlazado contra OpenSSL 1.1, que ya no
    # viene en Debian 12: se instala el paquete de Debian 11.
    deb="libssl1.1_${LIBSSL11_VERSION}_${TARGETARCH:-amd64}.deb"; \
    curl -fsSL -o /tmp/libssl1.1.deb "https://deb.debian.org/debian/pool/main/o/openssl/${deb}" \
      || curl -fsSL -o /tmp/libssl1.1.deb "https://archive.debian.org/debian/pool/main/o/openssl/${deb}"

# --- Etapa 2: imagen final ---
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libncursesw6 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=download /tmp/libssl1.1.deb /tmp/libssl1.1.deb
RUN DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/libssl1.1.deb && rm /tmp/libssl1.1.deb

COPY --from=download /opt/mta /opt/mta
COPY entrypoint.sh /usr/local/bin/mta-entrypoint
RUN chmod +x /usr/local/bin/mta-entrypoint

WORKDIR /opt/mta
EXPOSE 22003/udp 22005/tcp 22126/udp
ENTRYPOINT ["mta-entrypoint"]
