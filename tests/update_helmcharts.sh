#!/usr/bin/env bash

set -eu

IFS="
"

test -d tests || (
  echo -e "\n*** Run in top level of git repository\n"
  exit 1
)

grep -R -h 'helm repo add' docs/part* | sort | uniq | sh -

(
  for CHART in $(find docs/part* -name "*.md" -exec sed -n 's@helm upgrade --install --version \([^ ]*\).* \([^ ]*/[^ ]*\).*@\1 \2@p' {} \; | sort -k 2); do
    HELMCHART="${CHART##* }"
    CURRENT_DOC_HELMCHART_VERSION="${CHART% *}"
    LATEST_HELMCHART_VERSION=$(helm search repo "${HELMCHART}" --output json | jq -r ".[0].version")

    if [[ "${LATEST_HELMCHART_VERSION}" != "${CURRENT_DOC_HELMCHART_VERSION}" ]] && [[ -n "${LATEST_HELMCHART_VERSION}" ]]; then
      echo "${HELMCHART} | Current Doc: ${CURRENT_DOC_HELMCHART_VERSION} | Latest HelmChart version: ${LATEST_HELMCHART_VERSION}"
    fi
  done
) | column -s \| -t
