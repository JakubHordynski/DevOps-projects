Web deploy

Turn a standard Node/Astro web application into a highly optimized, production-ready container stack. Web Deploy provides a complete, lightweight Dockerized environment for serving the `web-solvro-docs` application using Nginx, secured with local HTTPS via Traefik, and monitored using Prometheus and Grafana.

Instead of deploying a massive 2.9GB development container, this project uses multi-stage building to reduce the image size to just 168MB, ensuring fast deployments and a minimized attack surface.

- Secured local HTTPS connections
- Real-time performance monitoring

## Features

- **Extreme Container Optimization:** Multi-stage Dockerfile reduces image size from 2.9GB to 168MB.
- **Local HTTPS:** Secure traffic routing using Traefik v3.0 and `mkcert` generated certificates.
- **Production Web Server:** Final stage utilizes lightweight Nginx for static file serving.
- **Advanced Monitoring:** Full observability stack with Prometheus and Grafana.
- **Real-Time Alerting:** Discord Webhook integration for downtime notifications.

## Requirements

- Docker
- Docker Desktop
- Node v24.22
- Git v2.56
- `mkcert` (for local SSL certificates)
