FROM debian:bullseye-slim

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends -o=Dpkg::Use-Pty=0 \
    curl \
    cron \
    jq \
    libzip-dev \
    unzip \
    zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log && \
    touch /var/log/cron.log


RUN (crontab -l ; echo "*/5 * * * * date >> /var/log/cron.log 2>&1") | crontab
COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]