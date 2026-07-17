# Docs

## Setup

### Collector

The collector runs on the PostgreSQL host as a Debian package managed by `systemd`. Supported: Debian 11–13, amd64, PostgreSQL 15–18.

#### 1. Prepare PostgreSQL

Create the monitoring role:

```sql
CREATE USER pgdozor_collector WITH PASSWORD 'CHANGE_ME' CONNECTION LIMIT 5;
GRANT pg_monitor TO pgdozor_collector;
```

Configure `postgresql.conf`:

```
# postgresql.conf
shared_preload_libraries = 'pg_stat_statements,auto_explain'
pg_stat_statements.track = top
pg_stat_statements.max = 20000
track_io_timing = on
compute_query_id = on

logging_collector = on
log_destination = 'jsonlog'
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = '1d'
log_rotation_size = '128MB'
log_timezone = 'UTC'
log_min_duration_statement = 1000
log_lock_waits = on
log_file_mode = 0640

auto_explain.log_format = 'json'
auto_explain.log_min_duration = 1000
auto_explain.log_analyze = on
auto_explain.log_buffers = on
auto_explain.log_timing = on
auto_explain.log_triggers = on
auto_explain.log_verbose = on
auto_explain.sample_rate = 0.5
```

`shared_preload_libraries` needs a restart; then create the extension:

```
systemctl restart postgresql
```

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Verify the configuration is complete:

```sh
psql -X -P pager=off "postgresql://postgres:PASSWORD@HOST:5432/postgres" -f check-postgres-config.sql
```

Log permissions should be handled by the package:

- The collector is added to the `postgres` group, so it can **read** the jsonlogs.
- The systemd unit holds the `CAP_FOWNER` capability, so it can **delete** rotated jsonlogs.

#### 2. Install the collector

```sh
curl -fsSL https://raw.githubusercontent.com/pgdozor/collector/master/scripts/install.sh | sudo sh
```

This installs the latest `.deb` from GitHub Releases and sets up:

- the binary at `/usr/bin/pgdozor-collector`,
- a dedicated `pgdozor-collector` system user (added to the `postgres` group),
- the systemd unit `pgdozor-collector.service` (enabled to start on boot),
- a config seeded at `/etc/pgdozor-collector.yml` (`root:pgdozor-collector`, `0640`).

Pin a version with `VERSION=1.2.3 curl … | sudo sh`.

#### 3. Configure the service

Edit `/etc/pgdozor-collector.yml` — set the backend URL, the collector token, and
the Postgres DSN (see `/etc/pgdozor-collector.yml.example` for the full schema):

```yaml
backend:
  url: https://backend.example.com:3000
  token: pgdc_CHANGE_ME

postgres: postgresql://pgdozor_collector@localhost:5432/postgres

logs:
  path: /var/log/postgresql
  delete_rotated: true
```

The config is `root:pgdozor-collector 0640` — it holds the token and DB password,
so keep it out of world-readable reach.

#### 4. Start and verify

```sh
sudo systemctl start pgdozor-collector
systemctl status pgdozor-collector
journalctl -u pgdozor-collector -f
```

A healthy start logs `pgdozor collector started` with the detected Postgres
version. Apply config changes with `systemctl restart pgdozor-collector`.

#### Upgrade / uninstall

```sh
# upgrade: re-run the installer — it pulls the newest release; your config is kept
curl -fsSL https://raw.githubusercontent.com/pgdozor/collector/main/scripts/install.sh | sudo sh

sudo apt-get remove pgdozor-collector   # keep config and state
sudo apt-get purge  pgdozor-collector   # also remove config, state, and the user
```

### Backend & Frontend (Kubernetes)

The backend and frontend deploy together to Kubernetes via one Helm chart
(`deploy/helm/pgdozor`). Prebuilt multi-arch images are published to GHCR
(`ghcr.io/pgdozor/backend`, `ghcr.io/pgdozor/frontend`), so no local build is
needed.

#### Prerequisites

- A Kubernetes cluster with an ingress controller (e.g. ingress-nginx).
- An **empty** PostgreSQL database for the backend's own store, reachable from the
  cluster. Its role must be able to `CREATE` tables and partitions. This is
  **separate** from the databases being monitored.
- A DNS record pointing at the ingress, and (recommended) TLS — cert-manager or a
  pre-created TLS secret.

#### 1. Install

Single-host mode (recommended): the dashboard and the Connect API share one
origin, so there is no CORS to configure and the session cookie flows cleanly.

```sh
helm install pgdozor ./deploy/helm/pgdozor \
  --set ingress.host=pgdozor.example.com \
  --set ingress.className=nginx \
  --set ingress.tls.enabled=true \
  --set ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt-prod \
  --set secret.values.DATABASE_URL='postgres://pgdozor:PASS@db-host:5432/pgdozor?sslmode=require'
```

Prefer a pre-created Secret over an inline DSN in production:

```sh
kubectl create secret generic pgdozor-db --from-literal=DATABASE_URL='postgres://…'
helm install pgdozor ./deploy/helm/pgdozor \
  --set ingress.host=pgdozor.example.com --set ingress.tls.enabled=true \
  --set secret.create=false --set secret.name=pgdozor-db
```

Or copy `deploy/helm/pgdozor/values.example.yaml`, edit it, and
`helm install pgdozor ./deploy/helm/pgdozor -f my-values.yaml`.

Schema migrations run automatically as an init container (goose, embedded in the
backend image) before the backend starts — no manual migrate step.

#### 2. First login and collectors

- Open `https://<host>` and log in. The **first** successful login bootstraps the
  super admin (choose the email + password).
- As super admin, go to **Admin → Collectors** and create a collector token. Give
  each collector its `pgdc_` token and point `backend.url` at
  `https://<host>` (single-host) — the collector setup above covers the rest.

#### 3. Upgrade

```sh
helm upgrade pgdozor ./deploy/helm/pgdozor -f my-values.yaml
```

Pin `backend.image.tag` / `frontend.image.tag` to a released version in
production rather than relying on the chart default.

#### Ingress topology

- **Single-host (default):** one hostname; Connect service paths
  (`/pgdozor.v1.*`) route to the backend, everything else to the frontend.
  `PUBLIC_API_URL` and `CORS_ALLOWED_ORIGINS` are derived automatically.
- **Dual-host:** set `ingress.dualHost.enabled=true` and
  `ingress.dualHost.apiHost=api.pgdozor.example.com`. The app host and API host
  **must share one registrable domain** (subdomains) — otherwise the `SameSite=Lax`
  session cookie will not flow from the dashboard to the API.

The frontend reads `PUBLIC_API_URL` at **runtime** (adapter-node), so the backend
URL is set at deploy time via the chart — no image rebuild to re-point it.
