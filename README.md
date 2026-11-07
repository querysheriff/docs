<p align="center">
  <img src="https://raw.githubusercontent.com/querysheriff/frontend/master/static/logo.svg" alt="QuerySheriff logo" width="96">
</p>

<h1 align="center">QuerySheriff docs</h1>

<p align="center">
  <a href="deployment.md">Deployment guide</a> ·
  <a href="deploy/helm/querysheriff/README.md">Helm chart</a> ·
  <a href="deployment.md#troubleshooting">Troubleshooting</a>
</p>

A collector runs on each monitored PostgreSQL server. The backend and dashboard run in Kubernetes and keep their data in PostgreSQL and ClickHouse.

Follow the [deployment guide](deployment.md): prepare PostgreSQL, create two databases, install with Helm, then add a collector on each server. To check a server's settings first:

```sh
sudo -u postgres psql -X -P pager=off -d postgres < check-postgres-config.sql
```

| Path | Contents |
| --- | --- |
| [`deployment.md`](deployment.md) | Deployment, upgrades and troubleshooting |
| [`check-postgres-config.sql`](check-postgres-config.sql) | Settings check for a monitored server |
| [`deploy/helm/querysheriff/`](deploy/helm/querysheriff/README.md) | Helm chart for the backend and frontend |
| [`deploy/k8s/`](deploy/k8s/README.md) | Optional in-cluster PostgreSQL and ClickHouse |
