# Harbor

The S3 bucket where Harbor will store container images
(registry and ChartMuseum) was already created using CloudFormation.

The ServiceAccount for Harbor's registry and ChartMuseum to access S3 without
additional secrets was created by `eksctl`.

Install Harbor:

```bash
HARBOR_ADMIN_PASSWORD="harbor_supersecret_admin_password"

helm repo add --force-update harbor https://helm.goharbor.io ; helm repo update > /dev/null
helm install --wait --version 1.5.1 --namespace harbor --values - harbor harbor/harbor << EOF
# https://github.com/goharbor/harbor-helm/blob/master/values.yaml
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
  # resourcePolicy: delete
  # persistentVolumeClaim:
  #   registry:
  #     size: 1Gi
  #   chartmuseum:
  #     size: 1Gi
  #   trivy:
  #     size: 1Gi
  # imageChartStorage:
  # # S3 is not working due to the bugs:
  # # https://github.com/goharbor/harbor/issues/12888
  # # https://github.com/goharbor/harbor-helm/issues/725
  #   type: s3
  #   s3:
  #     region: ${REGION}
  #     bucket: ${CLUSTER_FQDN}-harbor
  #     rootdirectory: harbor
  #     storageclass: REDUCED_REDUNDANCY
imagePullPolicy: Always
harborAdminPassword: ${HARBOR_ADMIN_PASSWORD}
EOF
```

Configure OIDC for Harbor:

```shell
curl -u "admin:${HARBOR_ADMIN_PASSWORD}" -X PUT "https://harbor.${CLUSTER_FQDN}/api/v2.0/configurations" -H "Content-Type: application/json" -d \
"{
  \"auth_mode\": \"oidc_auth\",
  \"self_registration\": \"false\",
  \"oidc_name\": \"Google\",
  \"oidc_endpoint\": \"https://accounts.google.com\",
  \"oidc_client_id\": \"${MY_GOOGLE_OAUTH_CLIENT_ID}\",
  \"oidc_client_secret\": \"${MY_GOOGLE_OAUTH_CLIENT_SECRET}\",
  \"oidc_scope\": \"openid,profile,email\",
  \"oidc_auto_onboard\": \"true\"
}"
```

Enable automated vulnerability scan after each "image push" to the project:
`library`:

```bash
PROJECT_ID=$(curl -s -u "admin:${HARBOR_ADMIN_PASSWORD}" -X GET "https://harbor.${CLUSTER_FQDN}/api/v2.0/projects?name=library" | jq ".[].project_id")
curl -s -u "admin:${HARBOR_ADMIN_PASSWORD}" -X PUT "https://harbor.${CLUSTER_FQDN}/api/v2.0/projects/${PROJECT_ID}" -H  "Content-Type: application/json" -d \
"{
  \"metadata\": {
    \"auto_scan\": \"true\"
  }
}"
```

Create new Registry Endpoint:

```bash
curl -X POST -H "Content-Type: application/json" -u "admin:${HARBOR_ADMIN_PASSWORD}" "https://harbor.${CLUSTER_FQDN}/api/v2.0/registries" -d \
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
  curl -X POST -H "Content-Type: application/json" -u "admin:${HARBOR_ADMIN_PASSWORD}" "https://harbor.${CLUSTER_FQDN}/api/v2.0/replication/policies" -d \
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
  POLICY_ID=$(curl -s -H "Content-Type: application/json" -u "admin:${HARBOR_ADMIN_PASSWORD}" "https://harbor.${CLUSTER_FQDN}/api/v2.0/replication/policies" | jq ".[] | select (.filters[].value==\"${DOCKER_HUB_REPOSITORY}\") .id")
  curl -X POST -H "Content-Type: application/json" -u "admin:${HARBOR_ADMIN_PASSWORD}" "https://harbor.${CLUSTER_FQDN}/api/v2.0/replication/executions" -d "{ \"policy_id\": ${POLICY_ID} }"
done
```

After a while all images used by "bookinfo" application should be replicated
into `library` project and all should be automatically scanned.
