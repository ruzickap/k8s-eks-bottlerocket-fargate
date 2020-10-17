# Workload

Install the Ingress:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx
```

Install `podinfo`:

```bash
helm repo add sp https://stefanprodan.github.io/podinfo
helm install --version 3.2.3 podinfo sp/podinfo \
  --set ingress.enabled=true \
  --set "ingress.hosts[0]=podinfo.ruzickap-k8s-01.${MY_DOMAIN}"
```
