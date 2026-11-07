# Deploying QuerySheriff

A collector runs on each monitored PostgreSQL server and reports to the backend. The backend and dashboard run in Kubernetes behind one hostname. The backend keeps monitoring data in ClickHouse and configuration in PostgreSQL.

## Prerequisites

- Self-managed PostgreSQL 15 to 18 on each monitored server. Managed services such as Amazon RDS are not supported.
- Debian 11 to 13 (amd64) on those servers, or PostgreSQL in Kubernetes for the sidecar.
- A Kubernetes cluster with amd64 nodes, an Ingress controller and Helm 3.
- A DNS name and a TLS certificate for the dashboard.
- Network access from the collectors to `https://<host>/api`, and from the backend to its PostgreSQL (5432) and ClickHouse (9000, or 9440 with TLS).

## 1. Prepare the monitored PostgreSQL servers

On each server, create the role the collector connects as:

```sql
CREATE USER querysheriff_collector WITH PASSWORD 'CHANGE_ME' CONNECTION LIMIT 5;
GRANT pg_monitor TO querysheriff_collector;
```

Add these settings to `postgresql.conf`, tuning the durations and `sample_rate` for your server.

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

Restart PostgreSQL and create the extension:

```sh
sudo systemctl restart postgresql
sudo -u postgres psql -d postgres -c 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements;'
```

Check the result. The script lists every setting with its current and expected value, failures first:

```sh
curl -fsSLO https://raw.githubusercontent.com/querysheriff/docs/master/check-postgres-config.sql
sudo -u postgres psql -X -P pager=off -d postgres < check-postgres-config.sql
```

## 2. Create the backend PostgreSQL database

Use a server other than the ones you monitor:

```sql
CREATE USER querysheriff_backend WITH PASSWORD 'CHANGE_ME';
CREATE DATABASE querysheriff OWNER querysheriff_backend;
```

```
postgresql://querysheriff_backend:PASSWORD@HOST:5432/querysheriff?sslmode=require
```

To run it in the cluster instead, see [PostgreSQL in the cluster](deploy/k8s/README.md#postgresql).

## 3. Create the ClickHouse database

```sql
CREATE DATABASE querysheriff;
CREATE USER querysheriff_backend IDENTIFIED BY 'CHANGE_ME';
GRANT ALL ON querysheriff.* TO querysheriff_backend;
```

```
clickhouse://querysheriff_backend:PASSWORD@HOST:9000/querysheriff
clickhouse://querysheriff_backend:PASSWORD@HOST:9440/querysheriff?secure=true
```

To run it in the cluster instead, see [ClickHouse in the cluster](deploy/k8s/README.md#clickhouse).

## 4. Install the backend and frontend

Clone this repository and create the namespace:

```sh
git clone https://github.com/querysheriff/docs.git
cd docs
kubectl create namespace querysheriff
```

Put the database URLs from steps 2 and 3 into a Secret:

```sh
kubectl -n querysheriff create secret generic querysheriff-backend \
  --from-literal=POSTGRES_URL='postgresql://querysheriff_backend:PASSWORD@HOST:5432/querysheriff?sslmode=require' \
  --from-literal=CLICKHOUSE_URL='clickhouse://querysheriff_backend:PASSWORD@HOST:9000/querysheriff'
```

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

Install the chart:

```sh
helm install querysheriff deploy/helm/querysheriff -n querysheriff -f my-values.yaml
```

The [chart README](deploy/helm/querysheriff/README.md) lists every value.

## 5. Create collector tokens

Open `https://<host>` and log in right away: the first login creates the super admin.

For each monitored server, go to Admin > Collectors, enter the name the dashboard should show (e.g. `orders-db-1`) and copy the token. It's shown only once.

## 6. Install the collector

### On a Debian host

```sh
curl -fsSL https://raw.githubusercontent.com/querysheriff/collector/master/scripts/install.sh | sudo sh
```

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

`logs.path` must be the server's `log_directory`. The [commented example](https://github.com/querysheriff/collector/blob/master/packaging/querysheriff-collector.yml.example) describes every key.

Start the service and watch its log:

```sh
sudo systemctl start querysheriff-collector
journalctl -u querysheriff-collector -f
```

### As a sidecar in Kubernetes

Run the `ghcr.io/querysheriff/collector` image as a second container in the PostgreSQL pod:

- Share PostgreSQL's log directory through a volume and set `logs.path` to its mount path.
- Run it with the PostgreSQL user's UID and GID (999 in the official `postgres` image).
- Mount the config at `/etc/querysheriff-collector.yml` from a Secret.
- Connect to PostgreSQL over `127.0.0.1`.

[`deploy/k8s/querysheriff-postgres.yaml`](deploy/k8s/querysheriff-postgres.yaml) is a complete example.

## 7. Verify the deployment

```sh
kubectl -n querysheriff get pods
kubectl -n querysheriff logs job/querysheriff-migrate
```

The api, jobs and frontend pods should be `Running`, and the migrate log should end with `migrations applied`. On each monitored host, the collector log should show `querysheriff collector started`.

Within a minute the server gets a green dot in the dashboard's server picker. To test the whole path, run a slow query on a monitored server:

```sh
sudo -u postgres psql -d postgres -c 'SELECT pg_sleep(2);'
```

It shows up on the Logs page within about 10 seconds, and on the Queries page within two minutes.

## Upgrades and removal

To upgrade a collector, run the install script again. For a sidecar, change the image tag.

To upgrade the backend or frontend, change its image tag in `my-values.yaml` and run:

```sh
helm upgrade querysheriff deploy/helm/querysheriff -n querysheriff -f my-values.yaml
```

To remove a collector, run `sudo apt-get purge querysheriff-collector`.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Collector exits with `unsupported PostgreSQL version` | Only PostgreSQL 15 to 18 is supported. |
| Collector exits with `failed to load config` | The error names the unknown key or missing value. |
| `invalid collector token` | The token is wrong or was deleted. Create a new one and restart the collector. |
| `activity snapshot failed` with a connection or TLS error | The collector can't reach `backend.url`. Check DNS, the firewall and the `/api` suffix. |
| `relation "pg_stat_statements" does not exist` | Create the extension in the database the collector connects to. |
| `pg_stat_statements must be loaded via "shared_preload_libraries"` | Add it to `shared_preload_libraries` and restart PostgreSQL. |
| `could not tail log file` with `permission denied` | Set `log_file_mode = 0640`. If PostgreSQL was installed after the collector, run `sudo usermod -aG postgres querysheriff-collector` and restart the collector. |
| No log events and no errors | Check that `log_destination` includes `jsonlog` and that `logs.path` equals `log_directory`. |
| `helm install` fails on the migrate hook | Read `kubectl -n querysheriff logs job/querysheriff-migrate`. Usually a wrong URL or password, or a ClickHouse user without rights. |
| The api pod never becomes ready | It can't reach PostgreSQL or ClickHouse. Check the URLs in the Secret. |
| Logging in sends you back to the login page | `ingress.tls.enabled` is `true` but the site is served over plain HTTP. |
| A server shows as unhealthy | Its collector hasn't reported for 5 minutes. It's down or can't reach the backend. |
