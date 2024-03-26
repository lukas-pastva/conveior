FROM golang:1.16-buster AS builder
WORKDIR /app
COPY ./source-code/conveior/go.* ./
RUN go mod download
COPY ./source-code/conveior/*.go ./
RUN go build -o /conveior
FROM debian:bullseye-slim

WORKDIR /usr/local/bin

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends -o=Dpkg::Use-Pty=0 \
    apt-transport-https \
    bc \
    ca-certificates \
    cron \
    curl \
    containerd \
    docker.io \
    jq \
    rsync \
    rclone \
    vim \
    libzip-dev \
    procps \
    s3cmd \
    s3fs \
    unzip \
    zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o /usr/local/bin/ && chmod +x /usr/local/bin/kubectl

# yq
RUN curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq

COPY --from=builder /conveior /usr/local/bin/conveior
COPY ./source-code/conveior/bin /usr/local/bin
RUN chmod -R +x /usr/local/bin

EXPOSE 80
USER root

RUN mkdir -p /var/log && touch /var/log/cron.log
RUN (crontab -l ; echo "0 19 * * * /usr/local/bin/backup.sh >/dev/null") | crontab && \
    (crontab -l ; echo "*/5 * * * * /usr/local/bin/metrics.sh >/dev/null") | crontab

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
