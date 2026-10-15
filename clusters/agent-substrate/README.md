# agent-substrate cluster (gke-demos-345619, us-central1)

This branch is Agent Substrate `v0.5.0` plus the changes needed to run it on
this cluster, where ax is being evaluated. It replaces
`agent-substrate-cluster-v0.4.0`; [UPGRADE-v0.5.md](UPGRADE-v0.5.md) is the
runbook for moving the cluster from that branch to this one (a fresh install:
v0.4 to v0.5 can't be upgraded in place). [UPGRADE-v0.4.md](UPGRADE-v0.4.md)
is kept for history and for its smoke tests.

## Changes from v0.5.0

- `manifests/ate-install/postgres/postgres.yaml`: `nodeSelector:
  cloud.google.com/compute-class: n4-preferred`. Postgres requests 2 CPU,
  which the default pool's e2-medium nodes can't fit. Cluster-specific.
- `manifests/ate-install/atenet-egress.yaml`: the same nodeSelector. The
  sdsmint sidecar requests 200m CPU / 512Mi.
- `manifests/ate-install/atelet.yaml`:
  - tolerates `cloud.google.com/compute-class=substrate-workers:NoSchedule`,
    the taint GKE puts on every node of the workers' ComputeClass. Stock atelet
    tolerates only `ate.dev/sandboxClass`.
  - `nodeSelector: ate.dev/worker-node: "true"`. v0.5 removed the version
    label (#1812), so stock atelet runs on every node it tolerates, including
    the crowded e2-medium nodes, where it now requests 100m / 256Mi with the
    new objectstore-plugin sidecar at `ate-node-critical` priority. The
    `substrate-workers` ComputeClass stamps the label on its nodes
    (`nodePoolConfig.nodeLabels`). A neutral label is used rather than
    selecting `cloud.google.com/compute-class` from a DaemonSet, which is
    unverified on GKE. **Any other node that should host workers (the C4
    snapshot-test pool, the hostname fallback) needs the label too.**
- `manifests/ate-install/atenet-router.yaml`: `--parked-request-budget=60s`
  and `terminationGracePeriodSeconds: 120`. The default 5s budget is shorter
  than a cold resume after a long suspend, which then gets a 504 with no
  Retry-After (still true in v0.5).
- `hack/ate-selector/`: sets or clears an actor's `worker_selector`
  (kubectl-ate still can't). Build: `go build -o ate-selector ./hack/ate-selector`.
- `clusters/agent-substrate/`: this directory.

Dropped from the v0.4.0 branch:

- The postgres `storageClassName: dynamic-rwo` patch. `install.sh` sets
  `ATE_API_POSTGRES_STORAGE_CLASS=dynamic-rwo` instead (#2314; the setting is
  `ateapi.postgres.storageClass` / `--ateapi-postgres-storage-class`).
- The version pin: `VERSION` no longer names a node label or an atelet
  DaemonSet, the ComputeClass no longer stamps `ate.dev/substrate-version`,
  and the WorkerPools no longer select it.

## Install and operate

```sh
clusters/agent-substrate/install.sh                         # deploy or re-apply ate-system
kubectl --context agent-substrate apply -f clusters/agent-substrate/computeclass-substrate-workers.yaml
kubectl --context agent-substrate apply -f clusters/agent-substrate/workerpool.yaml
```

- `install.sh` installs the prebuilt `v0.5.0` images from
  `us-central1-docker.pkg.dev/gke-demos-345619/ax/substrate` (built with
  `VERSION=v0.5.0 go run ./cmd/ate-setup publish release-images`; digests in
  UPGRADE-v0.5.md), pinned to the digests their tags name at install time.
  `FROM_SOURCE=1 install.sh` builds everything instead (ko, plus docker for
  `envoy-dataplane`).
- `install.sh deploy atelet` re-renders only the atelet DaemonSet.
- Uninstall: `install.sh delete ate-system`. It deletes `ate-system`
  (postgres volume included), `podcertificate-controller-system` and the
  CRDs (and with them every WorkerPool).
- ate-setup records each deploy in `~/.cache/ate-setup/installs/` (v0.5 adds
  `cluster.substrateVersion`). Keep the record: future upgrades key off it.
- `ACTOR_JWT_ISSUER` is left at ate-setup's default `https://idp.ate-system.svc`.
- Snapshot bucket: `gs://ate-snapshots-gke-demos-345619-agent-substrate-us-central1`.
  ate-api-server and atelet (and their new objectstore-plugin sidecars, which
  run under the same ServiceAccounts) reach it through Workload Identity.
- Postgres (bundled): database `atepg`, schema `substrate`. v0.5 logs in with
  pod certificates (`substrate_owner_user`, `substrate_readwrite_user`);
  passwords are disabled (#2266).

## Workers

- ComputeClass `substrate-workers`: N4, then C4 (same Xeon 8581C, so FULL
  snapshots restore across them), auto-created pools, taint
  `ate.dev/sandboxClass=gvisor:NoSchedule`, label `ate.dev/worker-node=true`.
- `workerpool.yaml`: `ax-pool`, 4 replicas, `sandboxClasses: [{name: gvisor}]`
  (no `configRef`: follows the class default `gvisor-default`), selects only
  the class (NAP refuses pods that also select a custom label), and sets
  `template.resources` so each worker advertises 500m / 1Gi instead of the
  whole node. The limits are also the memory cgroup every actor on that
  worker shares; re-tune them after the smoke tests.
- `workerpool-hostname.yaml`: fallback when the class can't get capacity.

## Network (new in v0.5)

- `ate-system` denies ingress by default (#2522). The API (:443) admits
  ate-system's own components and **namespaces labeled
  `ate.dev/api-access=true`**: `ax-system` and `substrate-scope` need it.
- The router's plain HTTP (:80) stays open to every namespace
  (`--ingress-auth-mode=deprecated-insecure`, the default), so lookout-ax,
  substrate-scope and `ax-system/cred-curl` keep working unchanged.
- The router's `/statusz` (4040) is loopback-only: use
  `kubectl -n ate-system port-forward deploy/atenet-router 4040:4040`.
- DNS inside an actor resolves **only hostnames its egress policy allows**
  (#2524); anything else gets REFUSED. An ax task with no `egress:` gets no
  policy and resolves nothing.
- Link-local (`169.254.0.0/16`) egress is rejected in the sandbox (#2319).
- The egress gateway refuses outbound WebSocket upgrades (#1634).

## Credential injection

Unchanged from v0.4: the installer deploys the bundled Kubernetes Secrets
provider (`ATE_CREDENTIAL_PROVIDER={"name":"k8s.io"}`) with a NetworkPolicy
that admits only `atenet-egress`. The namespace policy ConfigMap
`ate-system/k8s-credential-provider-namespace-policy` is created empty and
must be re-applied after every fresh install, then the provider restarted:

```yaml
namespace-policy.yaml: |
  policies:
  - atespace: cred-test
    allowedNamespaces:
    - ate-credentials
```

v0.5 also lets a policy inject an `actor_jwt` header minted by the gateway
(no provider needed); the JWT claims moved to `actor.ate.dev`.
See `egress-policy-example.yaml`.

## Things to know on this version

- Nothing from v0.4 carries over: v0.4 snapshots don't restore (new gVisor
  `v3` asset, fs-checkpointed durable dirs), and v0.4 ActorTemplates read back
  with an empty `sandboxClass` (#2586).
- Durable dirs are gVisor tmpfs now: their contents count against the actor's
  memory.
- ActorTemplates say `sandboxClass: "gvisor"` (a string, not
  `SANDBOX_CLASS_GVISOR`). `ACTOR_STATE_PAUSED` is gone.
- Health probes moved to :9091 on every component; :9090 is metrics only.
- kubectl-ate v0.5 (`bin/kubectl-ate-v0.5.0`): `-v` is now verbosity (it was
  `--version`), and `logs actors` is now `logs actor`.
- Authorization is still opt-in (`--experimental-enable-authz`); left off.
- Keep workers on one CPU platform: v0.5's runtime matching checks only the
  architecture (CPU features are a TODO).
