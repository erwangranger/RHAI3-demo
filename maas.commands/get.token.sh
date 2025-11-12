#!/bin/bash

export CLUSTER_DOMAIN=$(oc whoami --show-console | sed -E 's/.*apps\.//')
HOST="maas.apps.${CLUSTER_DOMAIN}"
echo "HOST: ${HOST}"

