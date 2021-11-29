# Harbor

The S3 bucket where Harbor will store container images
(registry and ChartMuseum) was already created using CloudFormation.

The ServiceAccount for Harbor's registry and ChartMuseum to access S3 without
additional secrets was created by `eksctl`.

Install `harbor`
[helm chart](https://artifacthub.io/packages/helm/harbor/harbor)
and modify the
[default values](https://github.com/goharbor/harbor-helm/blob/master/values.yaml).

```bash
helm repo add --force-update harbor https://helm.goharbor.io
helm upgrade --install --version 1.7.2 --namespace harbor --wait --values - harbor harbor/harbor << EOF
expose:
  tls:
    certSource: secret
    secret:
      secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
      notarySecretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
  ingress:
    hosts:
      core: harbor.${CLUSTER_FQDN}
      notary: notary.${CLUSTER_FQDN}
externalURL: https://harbor.${CLUSTER_FQDN}
persistence:
  enabled: false
  imageChartStorage:
    type: s3
    s3:
      region: ${AWS_DEFAULT_REGION}
      bucket: ${CLUSTER_FQDN}
      # This should be replaced by IRSA once these bugs will be fixed:
      # https://github.com/goharbor/harbor-helm/issues/725
      accesskey: ${AWS_ACCESS_KEY_ID}
      secretkey: ${AWS_SECRET_ACCESS_KEY}
      rootdirectory: /harbor
      storageclass: REDUCED_REDUNDANCY
harborAdminPassword: ${MY_PASSWORD}
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
EOF
```

Create ServiceMonitor to allow Prometheus to get metric data:

```bash
kubectl apply -f - << EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: harbor
  namespace: harbor
  labels:
    app: harbor
spec:
  selector:
    matchLabels:
      app: harbor
  namespaceSelector:
    matchNames:
    - harbor
  endpoints:
  - port: metrics
EOF
```

Wait for Harbor DNS to be ready:

```bash
while [[ -z "$(dig +nocmd +noall +answer +ttlid a "harbor.${CLUSTER_FQDN}")" ]]; do
  date
  sleep 5
done
```

Configure OIDC for Harbor:

```bash
curl -sk -u "admin:${MY_PASSWORD}" -X PUT "https://harbor.${CLUSTER_FQDN}/api/v2.0/configurations" -H "Content-Type: application/json" -d \
"{
  \"auth_mode\": \"oidc_auth\",
  \"email_from\": \"harbor@${CLUSTER_FQDN}\",
  \"email_host\": \"mailhog.mailhog.svc.cluster.local\",
  \"email_port\": 1025,
  \"self_registration\": false,
  \"oidc_name\": \"Dex\",
  \"oidc_endpoint\": \"https://dex.${CLUSTER_FQDN}\",
  \"oidc_client_id\": \"harbor.${CLUSTER_FQDN}\",
  \"oidc_client_secret\": \"${MY_PASSWORD}\",
  \"oidc_verify_cert\": false,
  \"oidc_scope\": \"openid,profile,email\",
  \"oidc_auto_onboard\": true
}"
```

Enable automated vulnerability scan after each "image push" to the project:
`library`:

```bash
PROJECT_ID=$(curl -sk -u "admin:${MY_PASSWORD}" -X GET "https://harbor.${CLUSTER_FQDN}/api/v2.0/projects?name=library" | jq ".[].project_id")
curl -sk -u "admin:${MY_PASSWORD}" -X PUT "https://harbor.${CLUSTER_FQDN}/api/v2.0/projects/${PROJECT_ID}" -H  "Content-Type: application/json" -d \
"{
  \"metadata\": {
    \"auto_scan\": \"true\"
  }
}"
```

Create new Registry Endpoint:

```bash
curl -sk -X POST -H "Content-Type: application/json" -u "admin:${MY_PASSWORD}" "https://harbor.${CLUSTER_FQDN}/api/v2.0/registries" -d \
"{
  \"name\": \"Docker Hub\",
  \"type\": \"docker-hub\",
  \"url\": \"https://hub.docker.com\",
  \"description\": \"Docker Hub Registry Endpoint\"
}"
```

Create new Replication Rule:

I'm going to replicate the "bookinfo" application used for testing Istio:
[https://istio.io/docs/examples/bookinfo/](https://istio.io/docs/examples/bookinfo/)
When the replication completes all images should be automatically scanned
because I'm going to replicate everything into `library` project which has
"Automatically scan images on push" feature enabled.

Create new Replication Rule and initiate replication:

```bash
COUNTER=0
for DOCKER_HUB_REPOSITORY in istio/examples-bookinfo-details-v1 istio/examples-bookinfo-ratings-v1; do
  COUNTER=$((COUNTER+1))
  echo "Replicating (${COUNTER}): ${DOCKER_HUB_REPOSITORY}"
  curl -sk -X POST -H "Content-Type: application/json" -u "admin:${MY_PASSWORD}" "https://harbor.${CLUSTER_FQDN}/api/v2.0/replication/policies" -d \
    "{
      \"name\": \"Replication of ${DOCKER_HUB_REPOSITORY}\",
      \"type\": \"docker-hub\",
      \"url\": \"https://hub.docker.com\",
      \"description\": \"Replication Rule for ${DOCKER_HUB_REPOSITORY}\",
      \"enabled\": true,
      \"src_registry\": {
        \"id\": 1
      },
      \"dest_namespace\": \"library\",
      \"filters\": [{
        \"type\": \"name\",
        \"value\": \"${DOCKER_HUB_REPOSITORY}\"
      },
      {
        \"type\": \"tag\",
        \"value\": \"1.1*\"
      }],
      \"trigger\": {
        \"type\": \"manual\"
      }
    }"
  POLICY_ID=$(curl -sk -H "Content-Type: application/json" -u "admin:${MY_PASSWORD}" "https://harbor.${CLUSTER_FQDN}/api/v2.0/replication/policies" | jq ".[] | select (.filters[].value==\"${DOCKER_HUB_REPOSITORY}\") .id")
  curl -sk -X POST -H "Content-Type: application/json" -u "admin:${MY_PASSWORD}" "https://harbor.${CLUSTER_FQDN}/api/v2.0/replication/executions" -d "{ \"policy_id\": ${POLICY_ID} }"
done
```

After a while all images used by "bookinfo" application should be replicated
into `library` project and all should be automatically scanned.

## CloudWatch retention

Set retention for all log groups which belongs to the cluster to 1 day:

```bash
for LOG_GROUP in $(aws logs describe-log-groups | jq -r ".logGroups[] | select(.logGroupName|test(\"/${CLUSTER_NAME}\")) .logGroupName"); do
  aws logs put-retention-policy --log-group-name "${LOG_GROUP}" --retention-in-days 1
done
```
