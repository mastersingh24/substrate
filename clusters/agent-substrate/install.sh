#!/usr/bin/env bash
# Install (or re-apply) Agent Substrate v0.3.0 on the agent-substrate GKE cluster
# from this branch, building images from source.
#
#   clusters/agent-substrate/install.sh                # deploy ate-system
#   clusters/agent-substrate/install.sh publish worker-images
#
# See README.md in this directory for what is specific to this cluster.
set -euo pipefail
cd "$(dirname "$0")/../.."

export NO_DEV_ENV=1
export PROJECT_ID=gke-demos-345619
export PROJECT_NUMBER=1067056737933
export CLUSTER_NAME=agent-substrate
export CLUSTER_LOCATION=us-central1
export GCE_REGION=us-central1
export KUBECTL_CONTEXT=agent-substrate
# The original install's bucket: ate-api-server and atelet already have access.
export BUCKET_NAME=ate-snapshots-gke-demos-345619-agent-substrate-us-central1
export KO_DOCKER_REPO=us-central1-docker.pkg.dev/gke-demos-345619/ax/substrate
export KO_DEFAULTPLATFORMS=linux/amd64
# The default Envoy egress dataplane did not forward allowed TLS on v0.3.0.
export ATE_ATENET_DATAPLANE=agentgateway
# The cluster's nodes, atelet DaemonSet and WorkerPool pin carry this label from
# the first install. Keep it, or ate-setup starts a second atelet next to the first.
export VERSION="${VERSION:-v0.3.0-dirty}"

if [[ $# -eq 0 ]]; then
  set -- deploy ate-system
fi
go run ./cmd/ate-setup --context "${KUBECTL_CONTEXT}" --rollout-timeout 300s "$@"
