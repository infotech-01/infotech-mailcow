FROM alpine:3.22.1

RUN apk add --no-cache iproute2 iptables wireguard-tools

COPY router.sh /usr/local/bin/router.sh
RUN chmod 0755 /usr/local/bin/router.sh

ENTRYPOINT ["/usr/local/bin/router.sh"]
