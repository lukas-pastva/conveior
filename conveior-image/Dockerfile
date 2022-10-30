FROM debian:bullseye-slim

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends -o=Dpkg::Use-Pty=0 \
    apt-transport-https \
    ca-certificates \
    cron \
    curl \
    docker.io \
    jq \
    libzip-dev \
    procps \
    vim \
    unzip \
    zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


RUN mkdir -p /var/log && \
    touch /var/log/cron.log && \
    mkdir /action && \
    chown 33 /action && \
    chmod 777 /action

COPY action /action
COPY entrypoint.sh cron.sh cron24.sh /
RUN chmod +x /entrypoint.sh /cron.sh /cron24.sh

RUN (crontab -l ; echo "*/5 * * * * /cron.sh >> /var/log/cron.log 2>&1") | crontab && \
    (crontab -l ; echo "0 19 * * * /cron24.sh >> /var/log/cron.log 2>&1") | crontab


WORKDIR /action

ENTRYPOINT ["/entrypoint.sh"]