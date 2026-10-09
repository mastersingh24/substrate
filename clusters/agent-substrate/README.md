# agent-substrate cluster (gke-demos-345619, us-central1)

This branch is Agent Substrate `v0.4.0` plus the changes needed to run it on
this cluster, where ax is being evaluated. It replaces
`agent-substrate-cluster-v0.3.0`; [UPGRADE-v0.4.md](UPGRADE-v0.4.md) is the
runbook for moving the cluster from that branch to this one.

## Changes from v0.4.0

- `manifests/ate-install/postgres/postgres.yaml`
  - `storageClassName: dynamic-rwo`. Without it the claim gets `standard-rwo`
    (pd-balanced), which can't attach to the C4 nodes the cluster autoscaler
    creates: `Error 400: pd-balanced disk type cannot be used by c4-highcpu-4
    machine type`. Reported upstream as agent-substrate/substrate#2298, fixed
    after v0.4.0 with an opt-in `--postgres-storage-class`.
  - `nodeSelector: cloud.google.com/compute-class: n4-preferred`. Postgres
    requests 2 CPU, which the default pool's e2-medium nodes can't fit. This
    one is specific to this cluster and isn't proposed upstream.
- `manifests/ate-install/atenet-egress.yaml`: `nodeSelector:
  cloud.google.com/compute-class: n4-preferred`. The gateway's sdsmint sidecar
  requests 200m CPU / 512Mi, which the e2-medium nodes can't fit. (On v0.3.0
  this patch was on `atenet-egress-with-sdsmint.yaml`; v0.4.0 made that the
  only egress manifest.)
- `clusters/agent-substrate/`: this directory.

Dropped from the v0.3.0 branch, because v0.4.0 covers them:

- The `agentgateway` dataplane default. v0.4.0 has one egress gateway, Envoy
  with TLS interception, and its `tlsPassthrough` rules work.
- `ATE_EXPERIMENTAL_USE_SDSMINT` and `ATE_CREDENTIAL_INJECTION_ENABLED`. Both
  are gone upstream. `install.sh` sets `ATE_CREDENTIAL_PROVIDER={"name":"k8s.io"}`,
  and the installer deploys the Kubernetes Secrets provider itself.
- Deploying `manifests/egress-credential-injection/k8s-credential-provider.yaml`
  by hand.

## Install and operate

```sh
clusters/agent-substrate/install.sh                         # deploy or re-apply ate-system
kubectl --context agent-substrate apply -f clusters/agent-substrate/workerpool.yaml
```

- `install.sh` installs the prebuilt `v0.4.0` images from
  `us-central1-docker.pkg.dev/gke-demos-345619/ax/substrate`, pinned to the
  digests their tags name at install time. The digests are listed in
  UPGRADE-v0.4.md. `FROM_SOURCE=1 install.sh` builds everything with ko instead.
- It pins `VERSION=v0.4.0`, the value of the node label
  `ate.dev/substrate-version`, the atelet DaemonSet suffix (`atelet-v0-4-0`)
  and the WorkerPool pin. Changing it makes ate-setup add a second atelet
  DaemonSet, as in a rolling upgrade.
- ate-setup labels only nodes that have no version label yet, and only when it
  runs. A node GKE adds or recreates later gets no atelet until `install.sh`
  runs again.
- Uninstall: `install.sh delete ate-system`. This deletes the whole `ate-system`
  namespace (postgres volume included), `podcertificate-controller-system`,
  the CRDs (which deletes every WorkerPool) and the node labels.
- ate-setup writes a record of each run's settings (see `--record-dir`). You
  can replay a run with `--config <file>`.
- Kubeconfig context: `agent-substrate`.
- Snapshot bucket: `gs://ate-snapshots-gke-demos-345619-agent-substrate-us-central1`.
  ate-api-server and atelet already have `objectAdmin` and `bucketViewer` on it
  through their Workload Identity principals. These are keyed by namespace and
  ServiceAccount name, which v0.4.0 keeps.
- Postgres (bundled): database `atepg`, schema `substrate`, owned by role
  `substrate_owner`. ate-api-server connects as `substrate_owner_user` (DDL)
  and `substrate_readwrite_user` (DML). The roles come from ate-setup
  (`pkg/postgressetup`). v0.3.0 used the `postgres` superuser and schema
  `public`.

## Worker node

All four workers run on `gke-agent-substrate-default-pool-447e9856-6v23`
(`workerpool.yaml` pins them by hostname). The node carries the taint
`ate.dev/sandboxClass=gvisor:NoSchedule`, which keeps the control plane, ax and
other Deployments off it. Pods that can still run there:

- worker pods. The controller adds `ate.dev/sandboxClass=gvisor` tolerations to
  them.
- atelet. It tolerates `ate.dev/sandboxClass`.
- GKE's own DaemonSets, which tolerate every taint.

`gcp-filestore-csi-node` doesn't tolerate the taint. It keeps its current pod
but wouldn't get a new one, and nothing on the node uses Filestore.

The taint is set on the node with kubectl, not on the node pool. If GKE
recreates the node (auto-repair, auto-upgrade), the new node has a different
name and no taint, and the WorkerPool's hostname pin leaves every worker
Pending. A dedicated one-node worker pool with the taint, one machine family
and auto-upgrade off would fix this for good (not done: GKE-level change).

## Credential injection (keeps model keys out of actors)

The egress gateway swaps a placeholder header for the real credential. The
credential never appears in the ActorTemplate, the sandbox or its snapshots.

- **Gateway and provider:** installed by `install.sh`
  (`ATE_CREDENTIAL_PROVIDER={"name":"k8s.io"}`). The provider gets a
  NetworkPolicy that admits only `app: atenet-egress` pods. Dataplane V2
  enforces it, so ad-hoc test pods can no longer call the provider directly.
- **Namespace policy:** ConfigMap `ate-system/k8s-credential-provider-namespace-policy`.
  The installer creates it empty, and only if it is absent. The provider reads
  it once at startup. This cluster's grant:

  ```yaml
  namespace-policy.yaml: |
    policies:
    - atespace: cred-test
      allowedNamespaces:
      - ate-credentials
  ```

  The Secret `ate-credentials/google-token` is kept fresh by `token-refresher`
  in the same namespace. It lives outside `ate-system`, so reinstalling
  Substrate doesn't touch it.
- **Actor:** a `systemInfo` volume whose `trustBundle` lists
  `names: [egress-mitm.ate.dev, system-roots.ate.dev]`, plus `SSL_CERT_FILE`
  (and `REQUESTS_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS`, ...) pointing at it.
  v0.4.0 removed the single `name` field: it is reserved, so a v0.3 client's
  value is dropped. Don't set `SSL_CERT_DIR`; it replaces the image's trust
  store (upstream #2044).
- **Policy:** an `https` rule with `effects.replaceHeaders`. See
  `egress-policy-example.yaml`.

## Things to know on this version

- Snapshots taken by v0.3.0 do not restore on v0.4.0 (upstream #2110: one
  rootfs tar per container). Nothing from the v0.3.0 install carries over.
- `snapshotConfig.onResume` and `onPause` are gone (#2105, #2309). A
  `DATA` snapshot always resumes by starting the containers fresh, with the
  durable dirs restored.
- Egress is default-deny per actor. Each actor needs an egress policy. The ax
  fork creates one per task.
- Authorization (OpenFGA, #1965/#1980) is off unless ate-api-server runs with
  `--experimental-enable-authz`. This install leaves it off. AccessPolicy RPCs
  are always enforced.
- WorkerPools can set `spec.template.serviceAccountName` (#2219). Without it,
  workers use the namespace's `default` ServiceAccount, as before.
- Reference task images by digest. A tag makes template creation fail with
  "actor template not found" (google/ax#366).
- Keep workers on one CPU type. Restoring a snapshot taken on an AMD host onto
  an Intel host fails with `incompatible FeatureSet`.
- The node state root moved from `/var/lib/ateom-gvisor` to `/var/lib/ate`.
  Nothing uses the old directory after the upgrade.
