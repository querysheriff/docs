# Databases in the cluster

These manifests run the backend's PostgreSQL and ClickHouse inside Kubernetes instead of outside it. Each is a single-replica StatefulSet without replication or backups.

| File | Creates |
| --- | --- |
| [`querysheriff-postgres.yaml`](querysheriff-postgres.yaml) | PostgreSQL 18 with a collector sidecar, Service `querysheriff-postgres:5432` |
| [`querysheriff-clickhouse.yaml`](querysheriff-clickhouse.yaml) | ClickHouse 25.12, Service `querysheriff-clickhouse:9000` |

Both use the `querysheriff` namespace. Apply them before installing the Helm chart.

## Storage

The volumes are 10Gi for PostgreSQL and 100Gi for ClickHouse, from the default StorageClass. To change either, edit `volumeClaimTemplates` before the first apply.

## PostgreSQL

On first start, the pod creates the `querysheriff` database, the `querysheriff_collector` role and the `pg_stat_statements` extension. Its collector sidecar monitors this database like any other server.

1. In the Secret, replace `POSTGRES_PASSWORD`, `BACKEND_PASSWORD` and `COLLECTOR_PASSWORD`. The collector password also appears in the DSN in `querysheriff-collector.yml`.

2. Apply the manifest:

   ```sh
   kubectl apply -f deploy/k8s/querysheriff-postgres.yaml
   kubectl -n querysheriff rollout status statefulset/querysheriff-postgres
   ```

3. Use this URL as `POSTGRES_URL`:

   ```
   postgresql://querysheriff_backend:BACKEND_PASSWORD@querysheriff-postgres:5432/querysheriff?sslmode=disable
   ```

4. After installing the chart, create a collector token for this server under Admin > Collectors, put it into `backend.token` in the Secret and restart the pod:

   ```sh
   kubectl -n querysheriff edit secret querysheriff-postgres
   kubectl -n querysheriff rollout restart statefulset/querysheriff-postgres
   ```

The sidecar reports to `http://querysheriff-api:3000/api`, which assumes the Helm release is named `querysheriff`.

## ClickHouse

1. In the Secret, replace `CLICKHOUSE_PASSWORD`.

2. Apply the manifest:

   ```sh
   kubectl apply -f deploy/k8s/querysheriff-clickhouse.yaml
   kubectl -n querysheriff rollout status statefulset/querysheriff-clickhouse
   ```

3. Use this URL as `CLICKHOUSE_URL`:

   ```
   clickhouse://querysheriff_backend:CLICKHOUSE_PASSWORD@querysheriff-clickhouse:9000/querysheriff
   ```
