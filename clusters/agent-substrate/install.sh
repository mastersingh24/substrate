#!/usr/bin/env bash
# Install (or re-apply) Agent Substrate v0.5.0 on the agent-substrate GKE cluster
# from this branch.
#
#   clusters/agent-substrate/install.sh                   # deploy ate-system
#   clusters/agent-substrate/install.sh delete ate-system # uninstall
#
# By default it installs the prebuilt v0.5.0 images already pushed to
# KO_DOCKER_REPO with `ate-setup publish release-images` (digests in
# UPGRADE-v0.5.md); the manifests still come from this checkout, so the
# cluster-specific patches apply. FROM_SOURCE=1 builds every image from the
# checkout with ko (and docker, for envoy-dataplane) instead.
#
# v0.4 -> v0.5 is not an in-place upgrade: tear down v0.4 with the v0.4
# branch's install.sh first (UPGRADE-v0.5.md).
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
  export ATE_IMAGE_TAG="${ATE_IMAGE_TAG:-v0.5.0}"
fi
# The bundled Kubernetes Secrets credential provider, deployed by the
# installer with a NetworkPolicy that admits only atenet-egress (as in v0.4).
k8s_credential_provider='{"name":"k8s.io"}'
export ATE_CREDENTIAL_PROVIDER="${ATE_CREDENTIAL_PROVIDER:-${k8s_credential_provider}}"
# The default standard-rwo (pd-balanced) cannot attach to the C4/N4 node
# postgres runs on; dynamic-rwo picks a disk type the node supports. Replaces
# v0.4's storageClassName patch (agent-substrate/substrate#2314). Applies only
# when the StatefulSet and its claim are created, i.e. on a fresh install.
export ATE_API_POSTGRES_STORAGE_CLASS="${ATE_API_POSTGRES_STORAGE_CLASS:-dynamic-rwo}"
# ACTOR_JWT_ISSUER is left to ate-setup's default (https://idp.ate-system.svc),
# which it writes to the ate-api-server-envvars Secret.
#
# v0.5 dropped the ate.dev/substrate-version node label and the versioned
# atelet DaemonSet (#1812); VERSION now only names the release in the install
# record (~/.cache/ate-setup/installs/). With prebuilt images it defaults to
# ATE_IMAGE_TAG anyway; set here so a FROM_SOURCE build is stamped the same.
export VERSION="${VERSION:-v0.5.0}"

if [[ $# -eq 0 ]]; then
  set -- deploy ate-system
fi
go run ./cmd/ate-setup --context "${KUBECTL_CONTEXT}" --rollout-timeout 300s "$@"
