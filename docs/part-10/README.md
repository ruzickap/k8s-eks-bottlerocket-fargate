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
HARBOR_ADMIN_PASSWORD="harbor_supersecret_admin_password"

helm repo add harbor https://helm.goharbor.io
helm install --version 1.5.3 --namespace harbor --wait --wait-for-jobs --values - harbor harbor/harbor << EOF
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
imagePullPolicy: Always
harborAdminPassword: ${HARBOR_ADMIN_PASSWORD}
EOF
```

Output:

```text
"harbor" has been added to your repositories
NAME: harbor
LAST DEPLOYED: Thu Dec 10 16:12:10 2020
NAMESPACE: harbor
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Please wait for several minutes for Harbor deployment to complete.
Then you should be able to visit the Harbor portal at https://harbor.k1.k8s.mylabs.dev
For more details, please visit https://github.com/goharbor/harbor
```

Configure OIDC for Harbor:

```bash
curl -sk -u "admin:${HARBOR_ADMIN_PASSWORD}" -X PUT "https://harbor.${CLUSTER_FQDN}/api/v2.0/configurations" -H "Content-Type: application/json" -d \
"{
  \"auth_mode\": \"oidc_auth\",
  \"self_registration\": \"false\",
  \"oidc_name\": \"Dex\",
  \"oidc_endpoint\": \"https://dex.${CLUSTER_FQDN}\",
  \"oidc_client_id\": \"harbor.${CLUSTER_FQDN}\",
  \"oidc_client_secret\": \"${MY_GITHUB_ORG_OAUTH_CLIENT_SECRET}\",
  \"oidc_verify_cert\": \"false\",
  \"oidc_scope\": \"openid,profile,email\",
  \"oidc_auto_onboard\": \"true\"
}"
```

Enable automated vulnerability scan after each "image push" to the project:
`library`:

```bash
PROJECT_ID=$(curl -sk -u "admin:${HARBOR_ADMIN_PASSWORD}" -X GET "https://harbor.${CLUSTER_FQDN}/api/v2.0/projects?name=library" | jq ".[].project_id")
curl -sk -u "admin:${HARBOR_ADMIN_PASSWORD}" -X PUT "https://harbor.${CLUSTER_FQDN}/api/v2.0/projects/${PROJECT_ID}" -H  "Content-Type: application/json" -d \
"{
  \"metadata\": {
    \"auto_scan\": \"true\"
  }
}"
```

Create new Registry Endpoint:

```bash
curl -sk -X POST -H "Content-Type: application/json" -u "admin:${HARBOR_ADMIN_PASSWORD}" "https://harbor.${CLUSTER_FQDN}/api/v2.0/registries" -d \
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
  curl -sk -X POST -H "Content-Type: application/json" -u "admin:${HARBOR_ADMIN_PASSWORD}" "https://harbor.${CLUSTER_FQDN}/api/v2.0/replication/policies" -d \
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
  POLICY_ID=$(curl -sk -H "Content-Type: application/json" -u "admin:${HARBOR_ADMIN_PASSWORD}" "https://harbor.${CLUSTER_FQDN}/api/v2.0/replication/policies" | jq ".[] | select (.filters[].value==\"${DOCKER_HUB_REPOSITORY}\") .id")
  curl -sk -X POST -H "Content-Type: application/json" -u "admin:${HARBOR_ADMIN_PASSWORD}" "https://harbor.${CLUSTER_FQDN}/api/v2.0/replication/executions" -d "{ \"policy_id\": ${POLICY_ID} }"
done
```

After a while all images used by "bookinfo" application should be replicated
into `library` project and all should be automatically scanned.

## CloudWatch retention

Set retention for all log groups which belongs to the cluster to 1 day:

```bash
for LOG_GROUP in $(aws logs describe-log-groups | jq -r ".logGroups[] | select(.logGroupName|test(\"/${CLUSTER_NAME}/|/${CLUSTER_FQDN}/\")) .logGroupName"); do
  aws logs put-retention-policy --log-group-name "${LOG_GROUP}" --retention-in-days 1
done
```