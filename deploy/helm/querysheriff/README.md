# querysheriff Helm chart

This chart installs the QuerySheriff backend and frontend behind one Ingress. The databases are not part of the chart; see the [deployment guide](../../../deployment.md) for what they need.

```sh
helm install querysheriff deploy/helm/querysheriff -n querysheriff -f my-values.yaml
```

[`values.example.yaml`](values.example.yaml) is a complete minimal values file.

## Resources

Names assume the release is called `querysheriff`.

| Resource | Kind | Notes |
| --- | --- | --- |
| `querysheriff-migrate` | Job | `pre-install` and `pre-upgrade` hook running `/querysheriff-migrate`. The release only proceeds once it succeeds. |
| `querysheriff-api` | Deployment, Service | Connect API on port 3000. Liveness `/healthz`, readiness `/readyz`. |
| `querysheriff-jobs` | Deployment | Alert scheduler. Always one replica, `Recreate` strategy, so scheduled work never runs twice. |
| `querysheriff-frontend` | Deployment, Service | Caddy serving the dashboard on port 3000. |
| `querysheriff` | Ingress | `/api` to the API, everything else to the frontend. |
| `querysheriff-backend` | Secret | Only with `secret.create: true`. Created as a hook so the migrate Job can read it. |

All pods run as non-root with a read-only root filesystem and every capability dropped. Nothing in the chart needs a persistent volume.

## Secret

The API, jobs and migrate containers load every key of the Secret as environment variables.

| Key | Required | Description |
| --- | --- | --- |
| `POSTGRES_URL` | yes | Backend PostgreSQL, e.g. `postgresql://querysheriff_backend:PASSWORD@HOST:5432/querysheriff?sslmode=require` |
| `CLICKHOUSE_URL` | yes | ClickHouse native protocol, e.g. `clickhouse://querysheriff_backend:PASSWORD@HOST:9000/querysheriff` |
| `RETENTION_DAYS` | no | Days of ClickHouse data to keep, 1 to 365. Default 30. Applied by the migrate Job. |

The chart sets the rest itself: `LISTEN_ADDR=0.0.0.0:3000`, `CORS_ALLOWED_ORIGINS` and `DASHBOARD_URL` to the Ingress origin, and `COOKIE_SECURE` to `ingress.tls.enabled`.

To keep credentials out of the values file, create the Secret yourself and point the chart at it:

```sh
kubectl -n querysheriff create secret generic querysheriff-backend \
  --from-literal=POSTGRES_URL='postgresql://...' \
  --from-literal=CLICKHOUSE_URL='clickhouse://...'
```

```yaml
secret:
  create: false
  name: querysheriff-backend
```

Or let the chart create it from `secret.values`:

```yaml
secret:
  values:
    POSTGRES_URL: postgresql://...
    CLICKHOUSE_URL: clickhouse://...
```

## Values

| Key | Default | Description |
| --- | --- | --- |
| `ingress.host` | `""` | Required. Hostname of the dashboard and the API. |
| `ingress.className` | `""` | IngressClass. Empty uses the cluster default. |
| `ingress.annotations` | `{}` | Annotations, e.g. a cert-manager issuer. |
| `ingress.tls.enabled` | `true` | The site is served over HTTPS. Also sets `COOKIE_SECURE` and the origin scheme. |
| `ingress.tls.secretName` | `""` | TLS Secret for the Ingress. Leave empty when the controller gets certificates itself. |
| `secret.create` | `true` | Create the Secret from `secret.values`. |
| `secret.name` | `""` | Secret name. Defaults to `<fullname>-backend`. |
| `secret.values` | `{}` | Secret contents when `secret.create` is `true`. |
| `backend.image.tag` | `""` | Required. Backend release, e.g. `0.0.26`. |
| `backend.image.repository` | `backend` | Appended to `image.registry`. |
| `backend.api.replicas` | `1` | API replicas. The API is stateless, so it scales out. |
| `backend.api.resources` | 100m CPU, 256Mi request; 512Mi limit | API container resources. |
| `backend.jobs.resources` | 50m CPU, 128Mi request; 256Mi limit | Scheduler container resources. |
| `frontend.image.tag` | `""` | Required. Frontend release, e.g. `0.0.21`. |
| `frontend.image.repository` | `frontend` | Appended to `image.registry`. |
| `frontend.replicas` | `1` | Frontend replicas. |
| `frontend.resources` | 50m CPU, 128Mi request; 256Mi limit | Frontend container resources. |
| `image.registry` | `ghcr.io/querysheriff` | Registry and organization for both images. |
| `image.pullPolicy` | `IfNotPresent` | Pull policy for every container. |
| `image.pullSecrets` | `[]` | Pull secrets for a private registry. |
| `nameOverride`, `fullnameOverride` | `""` | Override resource names. |

`backend.api`, `backend.jobs` and `frontend` also take `podAnnotations`, `nodeSelector`, `tolerations` and `affinity`.

Images are published for `linux/amd64` only. The backend and frontend are released separately, which is why both tags are required and have no default. The image tag is the release tag without the leading `v`.

## Upgrade and uninstall

```sh
helm upgrade querysheriff deploy/helm/querysheriff -n querysheriff -f my-values.yaml
helm uninstall querysheriff -n querysheriff
```

`helm upgrade` runs the migrate Job before it replaces any pod. Helm does not track hook resources, so `helm uninstall` leaves the `querysheriff-migrate` Job and a chart-created Secret behind. Delete them with `kubectl` if you no longer need them.
