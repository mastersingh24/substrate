#!/usr/bin/env bash
# Install (or re-apply) Agent Substrate v0.4.0 on the agent-substrate GKE cluster
# from this branch.
#
#   clusters/agent-substrate/install.sh                   # deploy ate-system
#   clusters/agent-substrate/install.sh delete ate-system # uninstall
#
# By default it installs the prebuilt v0.4.0 images already pushed to
# KO_DOCKER_REPO (see UPGRADE-v0.4.md for their digests); the manifests still
# come from this checkout, so the cluster-specific patches apply. FROM_SOURCE=1
# builds every image from the checkout with ko instead, as v0.3.0 did.
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
# The original install's bucket: ate-api-server and atelet already have access
# (Workload Identity principals for ns/ate-system/sa/{ate-api-server,atelet}).
export BUCKET_NAME=ate-snapshots-gke-demos-345619-agent-substrate-us-central1
export KO_DOCKER_REPO=us-central1-docker.pkg.dev/gke-demos-345619/ax/substrate
export KO_DEFAULTPLATFORMS=linux/amd64
if [[ "${FROM_SOURCE:-}" != 1 ]]; then
  export ATE_IMAGE_REPO="${ATE_IMAGE_REPO:-${KO_DOCKER_REPO}}"
  export ATE_IMAGE_TAG="${ATE_IMAGE_TAG:-v0.4.0}"
fi
# v0.4 has one egress gateway (Envoy, TLS-intercepting, with tlsPassthrough
# working), so the agentgateway override of v0.3.0 is gone. Credential
# injection graduated: the bundled Kubernetes Secrets provider is deployed by
# the installer itself, with a NetworkPolicy that admits only atenet-egress.
k8s_credential_provider='{"name":"k8s.io"}'
export ATE_CREDENTIAL_PROVIDER="${ATE_CREDENTIAL_PROVIDER:-${k8s_credential_provider}}"
# The node label ate.dev/substrate-version, the atelet DaemonSet name and the
# WorkerPool pin all derive from this. Keep it for every command against this
# install; a different value makes ate-setup add a second atelet DaemonSet, as
# in a rolling upgrade.
export VERSION="${VERSION:-v0.4.0}"

if [[ $# -eq 0 ]]; then
  set -- deploy ate-system
fi
go run ./cmd/ate-setup --context "${KUBECTL_CONTEXT}" --rollout-timeout 300s "$@"
