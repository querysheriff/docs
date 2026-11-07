# QuerySheriff Helm chart

The chart installs the QuerySheriff backend and frontend behind one Ingress. The databases are not part of it; see the [deployment guide](../../../deployment.md).

```sh
helm install querysheriff deploy/helm/querysheriff -n querysheriff -f my-values.yaml
```

[`values.example.yaml`](values.example.yaml) is a minimal values file.

## Resources

| Resource | Kind | Notes |
| --- | --- | --- |
| `querysheriff-migrate` | Job | Runs the migrations before every install and upgrade |
| `querysheriff-api` | Deployment, Service | API on port 3000 |
| `querysheriff-jobs` | Deployment | Alert scheduler, always one replica |
| `querysheriff-frontend` | Deployment, Service | Dashboard on port 3000 |
| `querysheriff` | Ingress | `/api` to the API, everything else to the frontend |
| `querysheriff-backend` | Secret | Only with `secret.create: true` |

## Secret

The backend reads these keys from the Secret:

| Key | Required | Description |
| --- | --- | --- |
| `POSTGRES_URL` | yes | Backend PostgreSQL URL |
| `CLICKHOUSE_URL` | yes | ClickHouse native protocol URL |
| `RETENTION_DAYS` | no | Days of data to keep, 1 to 365. Default 30. |

The chart sets the other backend settings itself.

To keep credentials out of the values file, create the Secret yourself and point the chart at it:

```yaml
secret:
  create: false
  name: querysheriff-backend
```

Or let the chart create it:

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
| `ingress.tls.enabled` | `true` | Serve over HTTPS. |
| `ingress.tls.secretName` | `""` | TLS Secret. Leave empty when the controller gets certificates itself. |
| `secret.create` | `true` | Create the Secret from `secret.values`. |
| `secret.name` | `""` | Secret name. Defaults to `<fullname>-backend`. |
| `secret.values` | `{}` | Secret contents when `secret.create` is `true`. |
| `backend.image.tag` | `""` | Required. Backend version, e.g. `0.0.26`. |
| `backend.image.repository` | `backend` | Appended to `image.registry`. |
| `backend.api.replicas` | `1` | API replicas. |
| `backend.api.resources` | 100m CPU, 256Mi request; 512Mi limit | API resources. |
| `backend.jobs.resources` | 50m CPU, 128Mi request; 256Mi limit | Scheduler resources. |
| `frontend.image.tag` | `""` | Required. Frontend version, e.g. `0.0.21`. |
| `frontend.image.repository` | `frontend` | Appended to `image.registry`. |
| `frontend.replicas` | `1` | Frontend replicas. |
| `frontend.resources` | 50m CPU, 128Mi request; 256Mi limit | Frontend resources. |
| `image.registry` | `ghcr.io/querysheriff` | Registry for both images. |
| `image.pullPolicy` | `IfNotPresent` | Pull policy. |
| `image.pullSecrets` | `[]` | Pull secrets for a private registry. |
| `nameOverride`, `fullnameOverride` | `""` | Override resource names. |

`backend.api`, `backend.jobs` and `frontend` also take `podAnnotations`, `nodeSelector`, `tolerations` and `affinity`.

## Upgrade and uninstall

```sh
helm upgrade querysheriff deploy/helm/querysheriff -n querysheriff -f my-values.yaml
helm uninstall querysheriff -n querysheriff
```

`helm uninstall` leaves the `querysheriff-migrate` Job and a chart-created Secret behind. Delete them with `kubectl` if you don't need them.
