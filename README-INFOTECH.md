# Infotech mailcow deployment

This public repository tracks mailcow `2026-07a` and adds the Infotech office/edge deployment. Runtime secrets exist only in Dokploy.

## Architecture

- `office/docker-compose.yml` runs the complete mailcow stack and all persistent volumes on `infotechserver`.
- `edge/docker-compose.yml` runs a web reverse proxy and a kernel mail router on Koara.
- Public mail TCP ports are DNATed through GRE over Tailscale. The office mail services retain the original client IP.
- New outbound SMTP connections from the mailcow network are policy-routed through the same tunnel and SNATed to Koara's public IP.
- Koara has no MTA, mail queue, mailbox, database, or persistent mail volume.

The fixed office mailcow subnet is `192.168.80.0/24`; it is intentionally outside the Docker networks already allocated on `infotechserver`.

## Dokploy

Create two Compose services from GitHub `main` and enable auto-deploy:

- Office: `office/docker-compose.yml`, server `Local`.
- Edge: `edge/docker-compose.yml`, server `Koara`.

Populate the office environment from `.env.infotech.example` with generated secrets. The edge service needs only the tunnel and routing variables.

## Public DNS and provider prerequisites

- `mail.infotech.wiki` must be an unproxied A record for `31.76.126.146`.
- The mail domain MX must point to `mail.infotech.wiki`.
- SPF, DKIM and DMARC must be published after the domain is created in mailcow.
- Koara must allow inbound and outbound TCP 25.
- PTR for `31.76.126.146` must be `mail.infotech.wiki`.

Do not treat the deployment as mail-ready until PTR, port 25, DNS authentication, inbound delivery and outbound delivery have all passed external tests.
