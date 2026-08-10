#!/bin/sh
set -eu

edge_ts="${EDGE_TAILSCALE_IP:?EDGE_TAILSCALE_IP is required}"
office_ts="${OFFICE_TAILSCALE_IP:?OFFICE_TAILSCALE_IP is required}"
edge_tunnel_ip="${EDGE_TUNNEL_IP:-10.254.254.1}"
office_tunnel_ip="${OFFICE_TUNNEL_IP:-10.254.254.2}"
mailcow_network="${MAILCOW_NETWORK:-192.168.80.0/24}"
public_if="${PUBLIC_INTERFACE:-ens3}"
tunnel="mailcow-edge"
chain="INFOTECH_MAIL_IN"
mail_ports="25,110,143,465,587,993,995,4190"

cleanup() {
    iptables -t nat -D PREROUTING -i "$public_if" -p tcp -m multiport --dports "$mail_ports" -j "$chain" 2>/dev/null || true
    iptables -t nat -F "$chain" 2>/dev/null || true
    iptables -t nat -X "$chain" 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s "$mailcow_network" -o "$public_if" -p tcp --dport 25 -j MASQUERADE 2>/dev/null || true
    iptables -t mangle -D FORWARD -o "$tunnel" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    iptables -D INPUT -i tailscale0 -p gre -s "$office_ts" -d "$edge_ts" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$public_if" -o "$tunnel" -p tcp -d "$office_tunnel_ip" -m multiport --dports "$mail_ports" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$tunnel" -o "$public_if" -p tcp -s "$office_tunnel_ip" -m multiport --sports "$mail_ports" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$tunnel" -o "$public_if" -p tcp -s "$mailcow_network" --dport 25 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$public_if" -o "$tunnel" -p tcp -d "$mailcow_network" --sport 25 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    ip route del "$mailcow_network" dev "$tunnel" 2>/dev/null || true
    ip link del "$tunnel" 2>/dev/null || true
}

trap cleanup EXIT
trap 'exit 0' INT TERM

cleanup
iptables -I INPUT 1 -i tailscale0 -p gre -s "$office_ts" -d "$edge_ts" -j ACCEPT
ip tunnel add "$tunnel" mode gre local "$edge_ts" remote "$office_ts" ttl 64
ip address add "$edge_tunnel_ip/30" dev "$tunnel"
ip link set "$tunnel" mtu 1200 up
sysctl -w "net.ipv4.conf.${tunnel}.rp_filter=0" >/dev/null
ip route replace "$mailcow_network" dev "$tunnel"

iptables -t nat -N "$chain"
iptables -t nat -A "$chain" -p tcp -j DNAT --to-destination "$office_tunnel_ip"
iptables -t nat -I PREROUTING 1 -i "$public_if" -p tcp -m multiport --dports "$mail_ports" -j "$chain"
iptables -t nat -I POSTROUTING 1 -s "$mailcow_network" -o "$public_if" -p tcp --dport 25 -j MASQUERADE
iptables -t mangle -I FORWARD 1 -o "$tunnel" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

iptables -I FORWARD 1 -i "$public_if" -o "$tunnel" -p tcp -d "$office_tunnel_ip" -m multiport --dports "$mail_ports" -j ACCEPT
iptables -I FORWARD 1 -i "$tunnel" -o "$public_if" -p tcp -s "$office_tunnel_ip" -m multiport --sports "$mail_ports" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -I FORWARD 1 -i "$tunnel" -o "$public_if" -p tcp -s "$mailcow_network" --dport 25 -j ACCEPT
iptables -I FORWARD 1 -i "$public_if" -o "$tunnel" -p tcp -d "$mailcow_network" --sport 25 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

echo "Forwarding public mail ports to $office_tunnel_ip over $tunnel"
while :; do
    sleep 3600 &
    wait $!
done
