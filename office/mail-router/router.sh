#!/bin/sh
set -eu

edge_public_ip="${EDGE_PUBLIC_IP:-31.76.126.146}"
edge_tunnel_ip="${EDGE_TUNNEL_IP:-10.254.254.1}"
office_tunnel_ip="${OFFICE_TUNNEL_IP:-10.254.254.2}"
mailcow_network="${MAILCOW_NETWORK:-192.168.80.0/24}"
mailcow_bridge="${MAILCOW_BRIDGE:-br-mailcow}"
route_table="${ROUTE_TABLE:-252}"
route_mark="${ROUTE_MARK:-0x19}"
wireguard_private_key="${WIREGUARD_PRIVATE_KEY:?WIREGUARD_PRIVATE_KEY is required}"
wireguard_peer_public_key="${WIREGUARD_PEER_PUBLIC_KEY:?WIREGUARD_PEER_PUBLIC_KEY is required}"
wireguard_port="${WIREGUARD_PORT:-51821}"
route_mask="0xff"
route_priority="10019"
tunnel="mailcow-edge"
key_file="/run/mailcow-edge.key"
mail_ports="25,110,143,465,587,993,995,4190"

cleanup() {
    iptables -t mangle -D PREROUTING -s "$mailcow_network" -p tcp --dport 25 -j MARK --set-xmark "$route_mark/$route_mask" 2>/dev/null || true
    iptables -t mangle -D PREROUTING -s "$mailcow_network" -p tcp -m multiport --sports "$mail_ports" -m conntrack --ctstate ESTABLISHED,RELATED -j MARK --set-xmark "$route_mark/$route_mask" 2>/dev/null || true
    iptables -t mangle -D FORWARD -o "$tunnel" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    iptables -D INPUT -i "$tunnel" -p udp --dport 41641 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i "$tunnel" -o "$mailcow_bridge" -p tcp -d "$mailcow_network" -m multiport --dports "$mail_ports" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$mailcow_bridge" -o "$tunnel" -p tcp -s "$mailcow_network" -m multiport --sports "$mail_ports" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$mailcow_bridge" -o "$tunnel" -p tcp -s "$mailcow_network" --dport 25 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$tunnel" -o "$mailcow_bridge" -p tcp -d "$mailcow_network" --sport 25 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    ip rule del fwmark "$route_mark/$route_mask" priority "$route_priority" table "$route_table" 2>/dev/null || true
    ip route flush table "$route_table" 2>/dev/null || true
    ip link del "$tunnel" 2>/dev/null || true
    rm -f "$key_file"
}

trap cleanup EXIT
trap 'exit 0' INT TERM

cleanup
ip link add "$tunnel" type wireguard
umask 077
printf '%s\n' "$wireguard_private_key" > "$key_file"
wg set "$tunnel" private-key "$key_file" listen-port "$wireguard_port" peer "$wireguard_peer_public_key" allowed-ips 0.0.0.0/0 endpoint "$edge_public_ip:$wireguard_port" persistent-keepalive 15
ip address add "$office_tunnel_ip/30" dev "$tunnel"
ip link set "$tunnel" mtu 1180 up

# Do not let Tailscale select this WireGuard link as a peer endpoint. That
# creates a Tailscale-over-WireGuard-over-Tailscale loop and periodic stalls.
iptables -I INPUT 1 -i "$tunnel" -p udp --dport 41641 -j DROP

ip route replace default dev "$tunnel" table "$route_table"
ip rule add fwmark "$route_mark/$route_mask" priority "$route_priority" table "$route_table"

iptables -t mangle -I PREROUTING 1 -s "$mailcow_network" -p tcp --dport 25 -j MARK --set-xmark "$route_mark/$route_mask"
iptables -t mangle -I PREROUTING 1 -s "$mailcow_network" -p tcp -m multiport --sports "$mail_ports" -m conntrack --ctstate ESTABLISHED,RELATED -j MARK --set-xmark "$route_mark/$route_mask"
iptables -t mangle -I FORWARD 1 -o "$tunnel" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

iptables -I FORWARD 1 -i "$tunnel" -o "$mailcow_bridge" -p tcp -d "$mailcow_network" -m multiport --dports "$mail_ports" -j ACCEPT
iptables -I FORWARD 1 -i "$mailcow_bridge" -o "$tunnel" -p tcp -s "$mailcow_network" -m multiport --sports "$mail_ports" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -I FORWARD 1 -i "$mailcow_bridge" -o "$tunnel" -p tcp -s "$mailcow_network" --dport 25 -j ACCEPT
iptables -I FORWARD 1 -i "$tunnel" -o "$mailcow_bridge" -p tcp -d "$mailcow_network" --sport 25 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

echo "Routing mailcow SMTP and edge replies through $tunnel"
while :; do
    sleep 3600 &
    wait $!
done
