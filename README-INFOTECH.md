# Infotech mailcow deployment

This public repository tracks mailcow `2026-07a` and adds the Infotech office/edge deployment. Runtime secrets exist only in Dokploy.

## Architecture

- `office/docker-compose.yml` runs the complete mailcow stack and all persistent volumes on `infotechserver`.
- Runtime bind-mounted configuration and certificates live at `/home/infochel/apps/mailcow-data`, outside Dokploy's replaceable Git checkout.
- `edge/docker-compose.yml` runs a web reverse proxy and a kernel mail router on Koara.
- Public mail TCP ports are DNATed through a dedicated WireGuard tunnel carried by the direct Tailscale peer connection. The office mail services retain the original client IP.
- New outbound SMTP connections from the mailcow network are policy-routed through the same tunnel and SNATed to Koara's public IP.
- Koara has no MTA, mail queue, mailbox, database, or persistent mail volume.
- Tailscale discovery is blocked inside the WireGuard tunnel to prevent recursive path selection and connection stalls.

The fixed office mailcow subnet is `192.168.80.0/24`; it is intentionally outside the Docker networks already allocated on `infotechserver`.

## Dokploy

Create two Compose services from GitHub `main` and enable auto-deploy:

- Office: `office/docker-compose.yml`, server `Local`.
- Edge: `edge/docker-compose.yml`, server `Koara`.

Populate the office environment from `.env.infotech.example` with generated secrets. The edge service needs only the tunnel and routing variables.

When updating the upstream mailcow tag, merge the new tracked `data/` files into the persistent data directory before deployment. Never replace or delete generated files in that directory.

## Public DNS and provider prerequisites

- `mail.infotech.wiki` must be an unproxied A record for `31.76.126.146`.
- The mail domain MX must point to `mail.infotech.wiki`.
- SPF, DKIM and DMARC must be published after the domain is created in mailcow.
- Koara must allow inbound and outbound TCP 25.
- PTR for `31.76.126.146` must be `mail.infotech.wiki`.

Do not treat the deployment as mail-ready until PTR, port 25, DNS authentication, inbound delivery and outbound delivery have all passed external tests.
