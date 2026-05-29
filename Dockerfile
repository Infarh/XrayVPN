FROM ghcr.io/mhsanaei/3x-ui:latest

SHELL ["/bin/sh", "-c"]

RUN apk add --no-cache \
    bash \
    curl \
    jq \
    sqlite \
    xxd

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 2053 443
VOLUME ["/etc/x-ui"]

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/app/x-ui"]
