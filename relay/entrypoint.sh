#!/bin/sh
set -eu

relay_hostname="${RELAY_HOSTNAME:?RELAY_HOSTNAME is required}"
relay_clients="${RELAY_CLIENTS:?RELAY_CLIENTS is required}"
relay_bind_ip="${RELAY_BIND_IP:?RELAY_BIND_IP is required}"
relay_port="${RELAY_PORT:-2525}"
message_size_limit="${RELAY_MESSAGE_SIZE_LIMIT:-104857600}"
queue_lifetime="${RELAY_QUEUE_LIFETIME:-1d}"

# Outbound-only null client. It owns no domain, accepts no local delivery and
# never stores mail: office mailcow hands finished, DKIM-signed messages to it
# because the mail edge provider blocks outbound TCP 25.
postconf -e "myhostname=${relay_hostname}"
postconf -e "myorigin=\$myhostname"
postconf -e "mydestination="
postconf -e "relay_domains="
postconf -e "local_transport=error:5.1.1 local delivery is disabled on this relay"
postconf -e "alias_maps="
postconf -e "alias_database="
# The container shares the host network namespace so that mynetworks sees the
# real client address instead of a Docker gateway. Listen on the private
# address only, and off port 25: the office marks port 25 and policy-routes it
# into the edge tunnel, which does not reach this host.
postconf -e "inet_interfaces=${relay_bind_ip}"
postconf -e "inet_protocols=ipv4"
postconf -M# smtp/inet 2>/dev/null || true
postconf -M "${relay_port}/inet=${relay_port} inet n - n - - smtpd"

# Only the office mailcow may relay. The published port is bound to a private
# address, so this is the second lock rather than the only one.
postconf -e "mynetworks=${relay_clients}"
postconf -e "smtpd_helo_required=yes"
postconf -e "smtpd_client_restrictions=permit_mynetworks,reject"
postconf -e "smtpd_relay_restrictions=permit_mynetworks,reject_unauth_destination"
postconf -e "smtpd_recipient_restrictions=permit_mynetworks,reject_unauth_destination"
postconf -e "disable_vrfy_command=yes"
postconf -e "smtpd_tls_security_level=none"

postconf -e "message_size_limit=${message_size_limit}"
postconf -e "maximal_queue_lifetime=${queue_lifetime}"
postconf -e "bounce_queue_lifetime=${queue_lifetime}"

postconf -e "smtp_tls_security_level=may"
postconf -e "smtp_tls_CApath=/etc/ssl/certs"
postconf -e "smtp_tls_loglevel=1"

postconf -e "maillog_file=/dev/stdout"

postfix set-permissions >/dev/null 2>&1 || true

exec postfix start-fg
