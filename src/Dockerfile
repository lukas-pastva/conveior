FROM debian:bookworm-slim

ARG KUBECTL_VERSION=v1.33.6
ARG YQ_VERSION=v4.54.1
ARG RCLONE_VERSION=v1.75.2

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
      bash ca-certificates curl jq mariadb-client procps unzip zip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# kubectl (checksum verified), yq, rclone
RUN curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256")  /usr/local/bin/kubectl" | sha256sum -c - && \
    chmod +x /usr/local/bin/kubectl && \
    curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" && \
    chmod +x /usr/local/bin/yq && \
    curl -fsSL -o /tmp/rclone.zip "https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip" && \
    unzip -q -j /tmp/rclone.zip '*/rclone' -d /usr/local/bin && chmod +x /usr/local/bin/rclone && rm -f /tmp/rclone.zip && \
    kubectl version --client >/dev/null && yq --version && rclone version | head -n 1

COPY lib/ /usr/local/lib/conveior/
COPY bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/conveior /usr/local/bin/entrypoint.sh /usr/local/bin/backup.sh

ENV CONVEIOR_LIB=/usr/local/lib/conveior \
    CONFIG_FILE_DIR=/home/config.yaml

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
