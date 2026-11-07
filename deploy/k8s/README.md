# Optional: databases in the cluster

The main [deployment guide](../../deployment.md) assumes the backend PostgreSQL and ClickHouse run outside Kubernetes. These two manifests run both inside the cluster instead, which is enough for a lab or a small installation.

Each is one StatefulSet with one replica and a single persistent volume. There is no replication, failover or backup. If you need any of those, use a managed service or an operator and give the backend its URLs as in the main guide.

| File | Creates |
| --- | --- |
| [`querysheriff-postgres.yaml`](querysheriff-postgres.yaml) | Secret, ConfigMap, Service `querysheriff-postgres:5432`, StatefulSet with PostgreSQL 18 and a collector sidecar |
| [`querysheriff-clickhouse.yaml`](querysheriff-clickhouse.yaml) | Secret, Service `querysheriff-clickhouse:9000` (native) and `:8123` (HTTP), StatefulSet with ClickHouse 25.12 |

Both use the `querysheriff` namespace. Apply them after creating the namespace and before installing the Helm chart, because the chart's migrate Job needs both databases.

## Storage

Each StatefulSet requests one `ReadWriteOnce` volume through `volumeClaimTemplates`: 10Gi for PostgreSQL, 100Gi for ClickHouse. Without `storageClassName` the cluster's default StorageClass is used. Set the class and size before the first apply, because a StatefulSet's volume claim template can't be changed afterwards.

With node-local storage such as `local-path`, the data lives on one node and the volume usually can't be expanded. Uncomment the `nodeSelector` to choose that node.

Deleting a StatefulSet keeps its PersistentVolumeClaim and the data. `kubectl delete pvc` removes them for good.

## PostgreSQL

The pod runs PostgreSQL with everything the collector needs already set: `pg_stat_statements`, `auto_explain` and jsonlog output to a shared `emptyDir`. A collector sidecar reads that directory, so the backend's own database shows up in the dashboard like any monitored server. On first start, the init script in the ConfigMap creates:

- the `querysheriff` database owned by `querysheriff_backend`
- the `querysheriff_collector` role with `pg_monitor`
- the `pg_stat_statements` extension in the `postgres` database

The args only set monitoring options. Add memory and WAL settings (`shared_buffers`, `work_mem`, `max_wal_size` and so on) for the node you run it on.

1. In the Secret, replace `POSTGRES_PASSWORD`, `BACKEND_PASSWORD` and `COLLECTOR_PASSWORD`. The collector password appears a second time, inside the DSN in `querysheriff-collector.yml`. The passwords are read only when the data directory is first initialized.

2. Apply the manifest and wait for the pod:

   ```sh
   kubectl apply -f deploy/k8s/querysheriff-postgres.yaml
   kubectl -n querysheriff rollout status statefulset/querysheriff-postgres
   ```

   The pod reports 2/2 right away. The collector logs rejected reports until step 4 gives it a real token.

3. Use this URL as `POSTGRES_URL` in the backend Secret:

   ```
   postgresql://querysheriff_backend:BACKEND_PASSWORD@querysheriff-postgres:5432/querysheriff?sslmode=disable
   ```

4. After the chart is installed, create a collector token for this server under Admin > Collectors. Put it into `backend.token` in the Secret and restart the pod:

   ```sh
   kubectl -n querysheriff edit secret querysheriff-postgres
   kubectl -n querysheriff rollout restart statefulset/querysheriff-postgres
   ```

The sidecar's `backend.url` is `http://querysheriff-api:3000/api`, the API Service of a Helm release named `querysheriff`. Change it if your release has another name.

## ClickHouse

ClickHouse holds every high-volume table. It gets no collector sidecar, since the collector only monitors PostgreSQL.

1. In the Secret, replace `CLICKHOUSE_PASSWORD`. The image creates the `querysheriff` database and the `querysheriff_backend` user on first start.

2. Apply the manifest:

   ```sh
   kubectl apply -f deploy/k8s/querysheriff-clickhouse.yaml
   kubectl -n querysheriff rollout status statefulset/querysheriff-clickhouse
   ```

3. Use this URL as `CLICKHOUSE_URL` in the backend Secret:

   ```
   clickhouse://querysheriff_backend:CLICKHOUSE_PASSWORD@querysheriff-clickhouse:9000/querysheriff
   ```

Size the volume for the retention period, not for growth. ClickHouse drops data older than `RETENTION_DAYS` (default 30) by itself, so disk use levels off. For scale, a month of data from one production database takes about 1.5 GiB.

The pod requests 1 CPU and 4Gi of memory, with an 8Gi limit. To run a query by hand:

```sh
kubectl -n querysheriff exec -it querysheriff-clickhouse-0 -- \
  clickhouse-client --user querysheriff_backend --password --database querysheriff
```
