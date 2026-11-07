# Deploying QuerySheriff

From an empty cluster to a verified installation: prepare PostgreSQL, create the two backend databases, install the Helm chart, and connect the collectors.

## Overview

| Part | Runs on | Connects to |
| --- | --- | --- |
| Collector | Each monitored PostgreSQL host, as a systemd service or a sidecar container | The local PostgreSQL, and the backend at `https://<host>/api` |
| Backend | Kubernetes, installed by the Helm chart | Backend PostgreSQL, ClickHouse, and Slack for alerts |
| Frontend | Kubernetes, installed by the same chart | Nothing. It serves static files. |
| Backend PostgreSQL | Anywhere the cluster can reach | |
| ClickHouse | Anywhere the cluster can reach | |

One hostname serves the dashboard and the API: the Ingress sends `/api` to the backend and everything else to the frontend. Browsers and collectors use the same `/api` URL.

The steps below go in dependency order. The backend must be running before you can create the token that a collector needs.

1. [Prepare the monitored PostgreSQL servers](#1-prepare-the-monitored-postgresql-servers)
2. [Create the backend PostgreSQL database](#2-create-the-backend-postgresql-database)
3. [Create the ClickHouse database](#3-create-the-clickhouse-database)
4. [Install the backend and frontend](#4-install-the-backend-and-frontend)
5. [Create collector tokens](#5-create-collector-tokens)
6. [Install the collector](#6-install-the-collector)
7. [Verify the deployment](#7-verify-the-deployment)

## Prerequisites

- Self-managed PostgreSQL 15 to 18 on every server you want to monitor. The collector reads the server's log files, so managed services such as Amazon RDS are not supported.
- For the Debian package: Debian 11 to 13 on amd64. Containerized PostgreSQL in Kubernetes can use the sidecar image instead.
- A Kubernetes cluster with an Ingress controller, for example ingress-nginx or Traefik, and Helm 3 or newer.
- A DNS name for the dashboard and a TLS certificate for it, from cert-manager or from the Ingress controller.
- A PostgreSQL database and a ClickHouse database for the backend, outside the cluster or inside it ([optional manifests](deploy/k8s/README.md)).

All images are published for `linux/amd64` only.

### Network

| From | To | Port |
| --- | --- | --- |
| Collector | Monitored PostgreSQL, usually on localhost | 5432 |
| Collector | Ingress, `https://<host>/api` | 443 |
| Browser | Ingress | 443 |
| Backend | Backend PostgreSQL | 5432 |
| Backend | ClickHouse, native protocol | 9000, or 9440 with TLS |
| Backend | Slack webhook URL, if Slack alerts are on | 443 |

### Credentials

| Credential | Created in | Stored in |
| --- | --- | --- |
| `querysheriff_collector` PostgreSQL role | Step 1, on each monitored server | The collector config, `postgres` |
| Backend PostgreSQL user | Step 2 | The chart Secret, `POSTGRES_URL` |
| ClickHouse user | Step 3 | The chart Secret, `CLICKHOUSE_URL` |
| Super admin email and password | Your first login | Backend PostgreSQL, password hashed with bcrypt |
| Collector token (`qsc_...`), one per monitored server | Step 5, in the dashboard | The collector config, `backend.token` |
| Slack webhook URL | The Alerts page in the dashboard | Backend PostgreSQL |

## 1. Prepare the monitored PostgreSQL servers

Do this on every server you want to monitor. It needs one PostgreSQL restart.

Create the role the collector connects as. `pg_monitor` gives read access to the statistics views and settings:

```sql
CREATE USER querysheriff_collector WITH PASSWORD 'CHANGE_ME' CONNECTION LIMIT 5;
GRANT pg_monitor TO querysheriff_collector;
```

Add these settings to `postgresql.conf`. The durations, sizes and `sample_rate` are examples to tune for your server.

```ini
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

| Setting | What it gives you |
| --- | --- |
| `pg_stat_statements`, `track = top`, `compute_query_id` | Statistics for each normalized query, the Queries page |
| `track_io_timing` | Time each query spent reading and writing blocks |
| `logging_collector`, `log_destination = 'jsonlog'` | Log files the collector can read. It reads jsonlog only, from the `.json` files PostgreSQL writes next to the `.log` files. |
| `log_min_duration_statement`, `log_lock_waits` | Slow query and lock wait events on the Logs page, and query samples on the query detail page |
| `auto_explain.*` | Execution plans for those samples |
| `log_file_mode = 0640` | Lets the collector, a member of the `postgres` group, read the log files |

`auto_explain.log_analyze` with `log_timing` times every plan node of every sampled statement, including the fast ones that never get logged. The PostgreSQL documentation warns that this can slow queries down a lot. `sample_rate = 0.5` limits it to half the statements; lower it on a busy server.

Restart PostgreSQL to load the libraries, then create the extension in the database the collector connects to (`postgres` in the examples here):

```sh
sudo systemctl restart postgresql
sudo -u postgres psql -d postgres -c 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements;'
```

Check the result with [`check-postgres-config.sql`](check-postgres-config.sql). It lists every setting with its current and expected value, failures first:

```sh
curl -fsSLO https://raw.githubusercontent.com/querysheriff/docs/master/check-postgres-config.sql
sudo -u postgres psql -X -P pager=off -d postgres < check-postgres-config.sql
```

## 2. Create the backend PostgreSQL database

The backend keeps users, sessions, servers, collector tokens and alert settings in PostgreSQL. The data is small. The database must be empty; the migrations create every table and need no extensions. Development and tests use PostgreSQL 17, the in-cluster manifest uses 18.

Keep it apart from the servers you monitor, so a failing production server doesn't take its monitoring down with it. A collector can still monitor it like any other server.

```sql
CREATE USER querysheriff_backend WITH PASSWORD 'CHANGE_ME';
CREATE DATABASE querysheriff OWNER querysheriff_backend;
```

The backend's connection URL:

```
postgresql://querysheriff_backend:PASSWORD@HOST:5432/querysheriff?sslmode=require
```

The backend doesn't use named prepared statements, so it also works through PgBouncer in transaction pooling mode.

To run this database in the cluster instead, see [PostgreSQL in the cluster](deploy/k8s/README.md#postgresql).

## 3. Create the ClickHouse database

ClickHouse stores the monitoring data: query statistics, samples, transaction activity and log events. Development, tests and the in-cluster manifest use ClickHouse 25.12. The backend needs a database and a user with full rights on it, because the migrations create and alter tables:

```sql
CREATE DATABASE querysheriff;
CREATE USER querysheriff_backend IDENTIFIED BY 'CHANGE_ME';
GRANT ALL ON querysheriff.* TO querysheriff_backend;
```

The backend connects over the native protocol:

```
clickhouse://querysheriff_backend:PASSWORD@HOST:9000/querysheriff
clickhouse://querysheriff_backend:PASSWORD@HOST:9440/querysheriff?secure=true
```

Data older than `RETENTION_DAYS` (default 30, at most 365) expires through ClickHouse TTLs, so there is no cleanup job and disk use levels off after one retention period. For scale, a month of data from one production database takes about 1.5 GiB.

To run ClickHouse in the cluster instead, see [ClickHouse in the cluster](deploy/k8s/README.md#clickhouse).

## 4. Install the backend and frontend

One Helm chart installs both. Clone this repository and create the namespace:

```sh
git clone https://github.com/querysheriff/docs.git
cd docs
kubectl create namespace querysheriff
```

Put the two database URLs from steps 2 and 3 into a Secret:

```sh
kubectl -n querysheriff create secret generic querysheriff-backend \
  --from-literal=POSTGRES_URL='postgresql://querysheriff_backend:PASSWORD@HOST:5432/querysheriff?sslmode=require' \
  --from-literal=CLICKHOUSE_URL='clickhouse://querysheriff_backend:PASSWORD@HOST:9000/querysheriff'
```

Add `--from-literal=RETENTION_DAYS=60` to keep more than 30 days of data.

Copy [`values.example.yaml`](deploy/helm/querysheriff/values.example.yaml) to `my-values.yaml` and set your hostname, Ingress class and TLS:

```yaml
ingress:
  host: querysheriff.example.com
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
  tls:
    enabled: true
    secretName: querysheriff-tls

secret:
  create: false
  name: querysheriff-backend

backend:
  image:
    tag: "0.0.26"

frontend:
  image:
    tag: "0.0.21"
```

The backend and frontend are released separately, so each needs its own image tag. The tags above are the versions the [system tests](https://github.com/querysheriff/system-tests) run together. Newer releases are listed on each repository's tags page.

Install the chart:

```sh
helm install querysheriff deploy/helm/querysheriff -n querysheriff -f my-values.yaml
```

### Backend

Before anything else starts, the `querysheriff-migrate` Job applies the PostgreSQL and ClickHouse migrations and sets the TTL from `RETENTION_DAYS`. If it fails, the install fails. The chart then starts the API (`querysheriff-api`) and the alert scheduler (`querysheriff-jobs`, always one replica). Both read the database URLs from the Secret. The chart derives the remaining settings from `ingress.*`: the allowed CORS origin, the dashboard URL in weekly reports, and the `Secure` flag on the session cookie, which follows `ingress.tls.enabled`.

The API is stateless. Raise `backend.api.replicas` to run more than one.

### Frontend

`querysheriff-frontend` serves the dashboard's static files with Caddy and needs no configuration. It calls the API at `/api` on its own origin, which is why both must sit behind the same hostname.

Neither component uses a persistent volume; all state is in the two databases. The [chart README](deploy/helm/querysheriff/README.md) lists every value and the resources the chart creates.

## 5. Create collector tokens

Open `https://<host>`. The first login on an empty database creates the super admin with the email and password you enter, so log in right after the install, before anyone else reaches the page.

Then, for every server you want to monitor:

1. Go to Admin > Collectors.
2. Enter the server name. This is the name the dashboard shows, e.g. `orders-db-1`.
3. Create the token and copy it. It is shown only once.

The token both authenticates the collector and tells the backend which server the data belongs to. Deleting a server's last token removes that server from QuerySheriff, along with user access and alert settings for it. Data already collected stays in ClickHouse until it expires.

Admin > Users adds more users and chooses which servers each one can see. Slack alerts are configured per server on the Alerts page.

## 6. Install the collector

### On a Debian host

```sh
curl -fsSL https://raw.githubusercontent.com/querysheriff/collector/master/scripts/install.sh | sudo sh
```

The script installs the latest `.deb` from the collector's GitHub releases. To pin a version, run `sudo env VERSION=0.0.11 sh` instead of `sudo sh`. The package sets up:

- the binary `/usr/bin/querysheriff-collector`
- a `querysheriff-collector` system user, added to the `postgres` group so it can read the logs
- the systemd unit `querysheriff-collector.service`, enabled at boot, with the `CAP_FOWNER` capability so it can delete rotated log files in PostgreSQL's log directory
- `/etc/querysheriff-collector.yml`, owned by `root:querysheriff-collector` with mode `0640`, and a commented example next to it

Edit `/etc/querysheriff-collector.yml`:

```yaml
backend:
  url: https://querysheriff.example.com/api
  token: qsc_CHANGE_ME

postgres: postgresql://querysheriff_collector:CHANGE_ME@localhost:5432/postgres

logs:
  path: /var/log/postgresql
  delete_rotated: true
```

`logs.path` must be the server's `log_directory`. PostgreSQL never deletes its own rotated log files, so `delete_rotated: true` lets the collector delete the ones that match `log_filename`; set `delete_rotated_json_only: true` if logrotate already handles the `.log` files. The collector rejects unknown keys. Every key is described in the [commented example](https://github.com/querysheriff/collector/blob/master/packaging/querysheriff-collector.yml.example).

Start the service and watch its log:

```sh
sudo systemctl start querysheriff-collector
journalctl -u querysheriff-collector -f
```

After a config change, run `sudo systemctl restart querysheriff-collector`.

### As a sidecar in Kubernetes

For PostgreSQL running in a pod, run the `ghcr.io/querysheriff/collector` image as a second container in the same pod:

- Share PostgreSQL's log directory with the collector through a volume, and set `logs.path` to its mount path.
- Run the collector with the PostgreSQL user's UID and GID (999 in the official `postgres` image), so it can read the `0640` log files.
- Mount the config file at `/etc/querysheriff-collector.yml`, e.g. from a Secret, since it holds the token and a password.
- Connect to PostgreSQL over `127.0.0.1`.

[`deploy/k8s/querysheriff-postgres.yaml`](deploy/k8s/querysheriff-postgres.yaml) is a complete example.

## 7. Verify the deployment

Check that every pod is running and the migrations finished:

```sh
kubectl -n querysheriff get pods
kubectl -n querysheriff logs job/querysheriff-migrate
```

The api, jobs and frontend pods should be `Running` and the migrate pod `Completed`, with `migrations applied` as the last line of its log. The api pod only turns ready once `/readyz` can reach both databases.

On a monitored host, the collector log should show `querysheriff collector started` with the PostgreSQL version and, when `logs.path` is set, `log collection started`. Repeated errors after that point to a problem; see [Troubleshooting](#troubleshooting).

Within a minute the server gets a green dot in the dashboard's server picker, which means its collector reported in the last 5 minutes. To test the whole path, run a slow query on the monitored server:

```sh
sudo -u postgres psql -d postgres -c 'SELECT pg_sleep(2);'
```

The query shows up on the Logs page as a slow query within about 10 seconds. On the Queries page, with the `postgres` database selected, it appears within two minutes, because the collector's first `pg_stat_statements` read after a start only sets the baseline.

## Upgrades and removal

To upgrade a collector, run the install script again. It installs the newest release, keeps the config and restarts the service if it was running. For a sidecar, change the image tag.

To upgrade the backend or frontend, change its image tag in `my-values.yaml` and run:

```sh
helm upgrade querysheriff deploy/helm/querysheriff -n querysheriff -f my-values.yaml
```

The migrate Job runs again before any pod is replaced.

The part of the API that collectors use only ever gains new optional fields, so an older collector keeps working with a newer backend.

To remove the collector, `sudo apt-get remove querysheriff-collector` keeps the config. `sudo apt-get purge querysheriff-collector` also deletes the config, `/var/lib/querysheriff-collector` and the system user.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| Collector exits with `unsupported PostgreSQL version` | Only PostgreSQL 15 to 18 is supported. |
| Collector exits with `failed to load config` | The YAML has an unknown key or a missing required value. The error names it. |
| `activity snapshot failed` with `invalid collector token` | The token is wrong or was deleted. Create a new one in step 5 and restart the collector. |
| `activity snapshot failed` with a connection or TLS error | The collector can't reach `backend.url`. Check DNS, the firewall and the `/api` suffix. |
| `statement delta failed` with `relation "pg_stat_statements" does not exist` | The extension isn't created in the database in the collector's `postgres` DSN. |
| `statement delta failed` with `pg_stat_statements must be loaded via "shared_preload_libraries"` | `shared_preload_libraries` lacks `pg_stat_statements`, or PostgreSQL wasn't restarted. |
| `could not tail log file` with `permission denied` | Set `log_file_mode = 0640`. If PostgreSQL was installed after the collector, the `postgres` group didn't exist yet: run `sudo usermod -aG postgres querysheriff-collector` and restart the collector. |
| No log events and no errors | Check that `log_destination` includes `jsonlog` and that `logs.path` equals `log_directory`. Only lines written after the collector started are sent. |
| `helm install` fails on the migrate hook | Read `kubectl -n querysheriff logs job/querysheriff-migrate`. Usually a wrong URL or password, or a ClickHouse user without rights on the database. |
| The api pod never becomes ready | `/readyz` can't reach PostgreSQL or ClickHouse. Check the URLs in the Secret and network policies. |
| After logging in you land on the login page again | `ingress.tls.enabled` is `true` but the site is served over plain HTTP. The session cookie is marked `Secure`, so the browser never sends it back. |
| A server shows as unhealthy, or the Monitoring stopped alert fires | The backend got no health report for 5 minutes (10 for the alert). The collector is down or can't reach the backend. |

For a closer look at the backend, port-forward the API and call its probes:

```sh
kubectl -n querysheriff port-forward svc/querysheriff-api 3000:3000
curl -i http://localhost:3000/readyz
```
