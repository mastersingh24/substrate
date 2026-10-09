# agent-substrate: v0.3.0 to v0.4.0

This runbook moves the agent-substrate cluster from branch
`agent-substrate-cluster-v0.3.0` to `agent-substrate-cluster-v0.4.0` with a
**fresh Substrate install**: tear down v0.3.0, then install v0.4.0. Run the
phases in order. Each phase lists how to verify it and how to roll it back.

## Decision: fresh install, not the upstream rolling upgrade

`docs/upgrade.md` describes a rolling upgrade that loses no actor state. On
this cluster and for this release, it would preserve nothing a fresh install
loses, and it carries more risk:

| Concern | Rolling upgrade | Fresh install |
|---|---|---|
| Snapshots (suspended actors, golden snapshots) | Unusable: v0.4.0 changed the snapshot layout with no compatibility path (#2110, #2283: "Old snapshots will not resume") | Discarded |
| Postgres state (actors, templates, atespaces, egress policies, tags) | Orphaned: v0.4.0's bundled database uses schema `substrate` owned by the new roles (#1752, #2025). v0.3.0's 21 tables stay in `public`, and ate-api-server starts on an empty schema | Discarded, with a new volume |
| Downtime | A full stop anyway: all four workers are on one node, and upgrade.md says a single worker node "stops fully during step 5" | A full stop |
| Preconditions | Not met: `default-pool` has auto-upgrade and auto-repair on, the node pool has no `ate.dev/substrate-version` label, and v0.3.0's sdsmint and agentgateway manifests and the hand-deployed credential provider don't match what v0.4.0 renders | Not needed |
| ateapi/atelet skew | #2105: atelet rejects the removed `DATA_ON_GOLDEN` scope, "upgrade ateapi and atelet together" | No skew |

**Lost either way:** every actor, ActorTemplate, atespace, egress policy and
tag, the v0.3.0 snapshots (they stay in GCS but can't be restored), and the
ax task records that point at them.

**Kept:** namespaces `ate-credentials` (Secrets `google-token` and `gemini`,
`token-refresher`), `ax-system`, `ax-workers`, `lookout-ax`, `substrate-scope`
and the triage namespaces; the snapshot bucket and its IAM; node pools; GKE
IAM.

**Regenerated:**
- The podcertificate CAs. ClusterTrustBundles keep their names but get new
  contents; consumers project them by signer, so a restart picks them up.
- The actor-ID CA and JWT pool, and the egress MITM CA.
- The Postgres volume.

**Recreated from backup:** ConfigMap `k8s-credential-provider-namespace-policy`.

## Breaking changes in v0.4.0 and what they mean here

| Change | Affects this install? | What changes |
|---|---|---|
| #2110, #2283 snapshot formats | Yes | Old snapshots can't be restored. Fresh install; optionally purge the old prefixes in the bucket after the soak (Phase 6) |
| #1752 separate PostgreSQL roles, #2025 bundled identities | Yes | ate-setup execs `psql` in `postgres-0` and creates roles `substrate_owner` and `substrate_readwrite`, logins `substrate_owner_user` and `substrate_readwrite_user`, and schema `substrate`. On the v0.3.0 database this would orphan `public`. A fresh volume avoids it. The `dynamic-rwo` and `n4-preferred` patches still apply (#2298 isn't fixed in v0.4.0) |
| #2012 uniform config package | Minor | Same env vars and flags. ate-setup writes a record of each run and accepts `--config`. Unknown env vars such as `ATE_EXPERIMENTAL_USE_SDSMINT` are silently ignored, so `install.sh` no longer sets them |
| #2015 non-MITM dataplanes removed | Yes | `atenet-egress-with-sdsmint.yaml` is now the only egress manifest, `atenet-egress.yaml`. The `n4-preferred` nodeSelector moved there. `install.sh` no longer forces `agentgateway`; the default, Envoy, is used. `tlsPassthrough` rules now work |
| #2101 credential injection graduated | Yes | `ATE_CREDENTIAL_PROVIDER={"name":"k8s.io"}` is required. The installer deploys the provider and a NetworkPolicy that admits only `atenet-egress`. The namespace-policy ConfigMap is created empty, only if absent: re-apply ours and restart the provider (Phase 4) |
| #2044 `SSL_CERT_DIR` removal | ax | The guidance is now `SSL_CERT_FILE` only. The deployed ax-server sets `SSL_CERT_DIR`; the ax v0.4 port drops it |
| #2049 `system-roots.ate.dev`, #2048 multiple bundle names | ax | `TrustBundleDataSource.name` (field 1) is reserved and replaced by `names`. **A v0.3 ax-server's trust bundle name is silently dropped**, so ax-server must be rebuilt against v0.4.0 with `names: [egress-mitm.ate.dev, system-roots.ate.dev]` (Phase 5) |
| #2219 WorkerPool `serviceAccountName` | No | Optional. ax-pool keeps the namespace's `default` ServiceAccount |
| #1965, #1980 authz (OpenFGA) | No | Off unless `--experimental-enable-authz`. OpenFGA tables are created in Postgres regardless |
| #2105 `onResume` removal, #2309 `onPause` removal | ax | A template that sets them is rejected over JSON. Over gRPC the fields are unknown and dropped. The ax v0.4 port sets only `onCommit` |
| #2193 actor events | No | Telemetry plumbing only |
| Worker/API proto changes (`worker_pod_ips`, `RegisterWorker`, `HardwareIdentity`) | substrate-scope | Wire-compatible for reads (a string field became a repeated string field). Rebuild substrate-scope against v0.4.0 when convenient |

## Images (built from tag v0.4.0, `VERSION=v0.4.0`, linux/amd64)

Repository `us-central1-docker.pkg.dev/gke-demos-345619/ax/substrate`, tag
`v0.4.0`. Built with `make build-release-images KO_DOCKER_REPO=<repo> VERSION=v0.4.0`
on 2026-10-09.

| Image | Digest |
|---|---|
| ateapi | `sha256:e66f61c015f4b944fecdc0ca3bb62f56a4783c71e89f27ea97fec12d2f2ffee4` |
| atecontroller | `sha256:1677b55a71fce63710a9aa01be5097711cc6bd3041d64336cf1192d8a7d3d51b` |
| atelet | `sha256:d71f5a812f19ab81dbc83a7ff76d06c4769eb7da15af4917aa517455c8504902` |
| atenet | `sha256:5262c9200db4fad4e04b1ca8969337b622add6adccda194e551ed0262d7e30c6` |
| kubernetes-secrets (credential provider) | `sha256:e8967336fecd7e8328d2bc5fd4a8522abbf593f87c7cf091251a8c8eee8fc7f2` |
| podcertcontroller | `sha256:3af4d257fdb5c688b04df7db9ca455c6b5c82aec4e9a180e698572bcd76fc38d` |
| ateom-gvisor (worker) | `sha256:a85055188241fb4ef6c59d7cd841c8855bc1204ffae5a3c187ba3b24395c13a6` |
| ateom-microvm | `sha256:242c07463a08ad21940728b35ec8547f126a7cb5a2155438a9aa741a91e74714` |
| envoy-dataplane | `sha256:7c7f914c43e23f1b68c2d1e5561d87ce22a73a4dbd09fdc451f145397839b819` |
| counter (demo) | `sha256:58120d883dc9dd16fc9fdd9b5d4959bd780b7df6390b9e04957b5d444d468daf` |
| egress (demo) | `sha256:e2222f3a1f5d7658615e1ac91f807282f82bfc0257658812cfa662d20a34635c` |
| fspersist (demo) | `sha256:de4620cd7a8ecf04c3e979cb8f4885d30dcdc63787596d8f17186d793db6ae94` |
| sandbox (demo) | `sha256:5372b1bee0b59d8c5b1b4975dfdecd7a0daaac7ca7bc6c844de111c51d2103ee` |

The router still runs the public `envoyproxy/envoy` image the manifest pins.

v0.3.0 images now running, for rollback (all built from source at `v0.3.0`):

| Component | Image |
|---|---|
| ate-api-server | `ateapi@sha256:53b3940014ffdd37608ea3c1a1920d3c5b0411a58ab4c61d829ebd883b4e62eb` |
| ate-controller | `atecontroller@sha256:72643819bf7b9e1578e18cd86f7fa333f2600752a2e562dc60df5f10c9705e73` |
| atelet | `atelet@sha256:7193a22722f4bdc96c5a546176245aad5c6c1c4a948bf1f2eebb503e1163a41c` |
| atenet (router, egress ext-proc, sdsmint) | `atenet@sha256:7bc6e23687b7f3541431fdbdebce4dd031403adbdc118bb9426b0f8fdcd2046c` |
| envoy-dataplane (egress) | `envoy-dataplane@sha256:e5769663641e0fdf54401fa1dd1b166ad45b02a914a82fa0e07675ef4c7b909d` |
| k8s-credential-provider | `kubernetes-secrets-dfca4b5adb39c5911ce3e539e84f64e7@sha256:c410bf49f5053653975e731808786d0f2ce11641d6257eeec1ff01fb8601dfbd` |
| podcertificate-controller | `podcertcontroller@sha256:0a15b90d543d8049d8cae0dfc4eac5f1a877dddaccd7dd53bba27da2794c9e92` |
| ateom-gvisor (WorkerPool) | `ateom-gvisor@sha256:38cdd65b437fd4f162f25da1509935072856df2521d7fdda17a11782186b703a` |
| ax-server | `ax/ax-server-340c3583cc4a989b584acf55b1619e8e@sha256:cc6db817e87dc6798c47592fa46bbfa70a0f6775f73dbaf1b8e4c7805f6b4087` |

## Expected downtime

Substrate and ax are unavailable from Phase 2 through Phase 5. Expect **30 to
45 minutes**:

- Teardown: about 5 minutes, most of it waiting for the namespace deletion.
- Install: 10 to 15 minutes. A new 500Gi PD is provisioned and attached to the
  `n4-preferred` node, and the podcertificate controller bootstraps.
- Consumers and the smoke test: about 10 minutes.

Phase 1 (rebalancing) causes no downtime: running pods aren't evicted.

## Conventions

```bash
V3=/home/user/projects/research/ax-substrate-eval/substrate       # branch agent-substrate-cluster-v0.3.0
V4=/home/user/projects/research/ax-substrate-eval/substrate-v0.4  # branch agent-substrate-cluster-v0.4.0
BAK=/home/user/projects/research/ax-substrate-eval/v04-migration/backup-v0.3.0
ATE3=/home/user/projects/research/ax-substrate-eval/bin/kubectl-ate          # v0.3 client
ATE4=/home/user/projects/research/ax-substrate-eval/bin/kubectl-ate-v0.4.0   # v0.4 client
K="kubectl --context agent-substrate"
WNODE=gke-agent-substrate-default-pool-447e9856-6v23
```

`$ATE4` is built from the v0.4.0 checkout:
`go build -ldflags "-X=github.com/agent-substrate/substrate/internal/version.Version=v0.4.0" -o $ATE4 ./cmd/kubectl-ate`.

## Phase 0: prerequisites and backups (no downtime)

1. **An ax-server image for v0.4.0 exists.** It needs ax built against
   `github.com/agent-substrate/substrate v0.4.0`, with:
   - `TrustBundleDataSource{Names: [egress-mitm.ate.dev, system-roots.ate.dev]}`
   - no `SSL_CERT_DIR`
   - no `onPause`/`onResume`
   - the per-task egress-policy creation from `task-egress-credentials`

   The port exists, uncommitted, in the ax worktree
   `.claude/worktrees/substrate-v04` (branch `substrate-v0.4`). It still has to
   be merged with `task-egress-credentials`, built and pushed. **Don't start
   Phase 2 without it:** the current ax-server can't create working tasks on
   v0.4.0. Write the image ref down as `AX_V4_IMAGE`.

2. **The v0.4.0 images resolve.**
   ```bash
   R=us-central1-docker.pkg.dev/gke-demos-345619/ax/substrate
   for i in ateapi atecontroller atelet atenet kubernetes-secrets podcertcontroller ateom-gvisor envoy-dataplane; do
     echo "$i $(crane digest $R/$i:v0.4.0)"; done
   ```
   Each digest must match the table above.

3. **Extra backups**, on top of `$BAK`:
   ```bash
   # The credential provider's namespace grant (recreated in Phase 4).
   $K -n ate-system get cm k8s-credential-provider-namespace-policy -o yaml > $BAK/cm-k8s-credential-provider-namespace-policy.yaml
   # Optional insurance for a full rollback: the v0.3.0 database.
   $K -n ate-system exec postgres-0 -c postgres -- pg_dump -U postgres -Fc atepg > $BAK/atepg-v0.3.0.dump
   # ax-redis has no volume: restarting it (Phase 5) wipes every ax task,
   # workspace and model. Record what to re-apply.
   for a in default cred-test ax-system; do
     ax --context agent-substrate -a $a get workspaces; ax --context agent-substrate -a $a get models
   done > $BAK/ax-config-inventory.txt
   # Then save each workspace and model with `ax describe`, or keep their
   # original apply files at hand (gke-demo, gke-clusters, mast-workspace in cred-test).
   ```

4. **Kept objects are healthy.** You should see `google-token` and
   `token-refresher` 1/1:
   ```bash
   $K -n ate-credentials get secret google-token && $K -n ate-credentials get deploy token-refresher
   ```

## Phase 1: take the worker node out of general scheduling (no downtime)

The worker node runs all four workers plus ate-api-server, atenet-router,
ax-server, ax-redis, gmp-operator, substrate-scope, kube-dns and two
konnectivity agents. That is 930m of its 940m CPU requested.

Put Substrate's own worker-node taint on it:

```bash
$K taint node $WNODE ate.dev/sandboxClass=gvisor:NoSchedule
```

Why this taint:
- The controller already adds the toleration `ate.dev/sandboxClass=gvisor` to
  every gVisor worker pod, on v0.3.0 (check:
  `$K -n ax-workers get pod -l ate.dev/worker-pool=ax-pool -o jsonpath='{.items[0].spec.tolerations}'`)
  and on v0.4.0. So workerpool.yaml needs no change.
- The atelet DaemonSet tolerates `ate.dev/sandboxClass:NoSchedule`.
- GKE's DaemonSets (anetd, netd, fluentbit, gke-metadata-server, pdcsi, gmp
  collector, node-local-dns) tolerate every `NoSchedule` taint. Only
  `gcp-filestore-csi-node` doesn't; it keeps its running pod, and the workers
  don't use Filestore.
- `NoSchedule` evicts nothing. Pods move off only when they are recreated.

That is least invasive: one object changes, and no Deployment needs an edit.
Anti-affinity or nodeSelectors would mean editing six Deployments in four
namespaces, some of them GKE-managed (gmp-operator, kube-dns), and the edits
would be lost on every redeploy.

Pods move off the node in these places:
- ate-api-server and atenet-router: the fresh install in Phase 4.
- ax-server and ax-redis: Phase 5.
- substrate-scope and gmp-operator: now, or in Phase 5:
  ```bash
  $K -n substrate-scope rollout restart deploy/substrate-scope
  $K -n gmp-system rollout restart deploy/gmp-operator
  ```
- kube-dns and konnectivity-agent: left alone. GKE reschedules them in time.

Capacity check: the other two e2-medium nodes have 233m and 118m CPU free.
The pods that move request 250m: ax-server 100m, ax-redis 100m,
substrate-scope 50m. ate-api-server, atenet-router, ate-controller,
gmp-operator and the credential provider request 0. It fits, with little
headroom. If something stays Pending:
- add a node to `default-pool`, or
- give ax-server and ax-redis `nodeSelector: cloud.google.com/compute-class: n4-preferred`,
  as postgres and atenet-egress have.

Verify:
```bash
$K get node $WNODE -o jsonpath='{.spec.taints}'
$K get pods -A -o wide --field-selector spec.nodeName=$WNODE | grep -v -E 'kube-system|gmp-system/collector|gcp-filestore|ax-workers|atelet'
```

Rollback: `$K taint node $WNODE ate.dev/sandboxClass=gvisor:NoSchedule-`.

The taint is node-local. If GKE auto-repair or auto-upgrade recreates the node,
the replacement has a new name and no taint, and the WorkerPool's hostname pin
breaks. That risk predates this change; see "Needs a human decision".

## Phase 2: stop ax (downtime starts)

```bash
$K -n ax-system scale deploy/ax-server --replicas=0
$K -n ax-system get cronjob task-reaper -o jsonpath='{.spec.suspend}'   # already true; keep it so
```

Rollback: `$K -n ax-system scale deploy/ax-server --replicas=1`.

## Phase 3: tear down v0.3.0

Run this from the **v0.3.0 checkout**. Its manifests match what is installed,
and its `install.sh` pins `VERSION=v0.3.0-dirty`.

```bash
cd $V3 && git checkout agent-substrate-cluster-v0.3.0 && git status --short   # must be clean

# 1. Delete the pool while ate-controller is still up, so it removes the
#    Deployment and the NetworkPolicy substrate-ax-pool-* itself.
$K -n ax-workers delete workerpool ax-pool --wait
$K -n ax-workers get deploy,pods,networkpolicy           # expect: nothing from ax-pool

# 2. Remove the hand-deployed credential provider (v0.3.0's delete doesn't
#    know it). Its namespace-policy ConfigMap was saved in Phase 0.
$K delete -f manifests/egress-credential-injection/k8s-credential-provider.yaml --ignore-not-found

# 3. Remove ate-system. This deletes the ate-system namespace (and the
#    postgres PVC; the StorageClass reclaims with Delete, so the PD goes too),
#    podcertificate-controller-system, the CRDs, cluster RBAC, and the node
#    label ate.dev/substrate-version.
clusters/agent-substrate/install.sh delete ate-system
```

Verify:
```bash
$K get ns ate-system podcertificate-controller-system   # NotFound
$K get crd | grep ate.dev                               # nothing
$K get nodes -L ate.dev/substrate-version               # column empty
$K get pv | grep ate-system                             # nothing (PD released)
$K get clusterrole,clusterrolebinding -o name | grep -E 'ate-|atelet|podcert|credential-provider'   # nothing, or only leftovers to delete
$K -n ate-credentials get secret google-token            # still there
```

Rollback: reinstall v0.3.0. See [Rollback](#rollback).

## Phase 4: install v0.4.0

Run this from the **v0.4.0 checkout**.

```bash
cd $V4 && git checkout agent-substrate-cluster-v0.4.0 && git status --short   # must be clean

# 1. The whole control plane, from the prebuilt v0.4.0 images.
#    install.sh sets ATE_IMAGE_REPO/ATE_IMAGE_TAG=v0.4.0, VERSION=v0.4.0 and
#    ATE_CREDENTIAL_PROVIDER={"name":"k8s.io"}, with the default Envoy dataplane.
clusters/agent-substrate/install.sh

# 2. The credential provider's namespace grant, then a provider restart
#    (it reads the policy only at startup).
$K -n ate-system apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-credential-provider-namespace-policy
  namespace: ate-system
data:
  namespace-policy.yaml: |
    policies:
    - atespace: cred-test
      allowedNamespaces:
      - ate-credentials
EOF
$K -n ate-system rollout restart deploy/k8s-credential-provider
$K -n ate-system rollout status deploy/k8s-credential-provider

# 3. The worker pool: 4 replicas on $WNODE, ateom-gvisor v0.4.0 by digest,
#    pinned to ate.dev/substrate-version=v0.4.0.
$K apply -f clusters/agent-substrate/workerpool.yaml
```

Verify:
```bash
$K get nodes -L ate.dev/substrate-version                   # every node v0.4.0
$K -n ate-system get ds -L ate.dev/substrate-version        # one DS, atelet-v0-4-0, DESIRED 3
                                                            # (the n4 node's compute-class taint keeps atelet off it, as before)
$K -n ate-system get pods -o wide                           # all Running; none on $WNODE except atelet
$K -n ate-system get deploy,sts -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[*].image}{"\n"}{end}'
                                                            # digests match the table above
$K -n ate-system get networkpolicy k8s-credential-provider
$K -n ate-system exec postgres-0 -c postgres -- psql -U postgres -d atepg -Atc \
  "select nspname, pg_get_userbyid(nspowner) from pg_namespace where nspname in ('public','substrate')"
                                                            # substrate|substrate_owner
$K -n ax-workers get workerpool ax-pool                     # READY 4
$K -n ax-workers get pods -o wide                           # 4 Running on $WNODE
$ATE4 --context agent-substrate get workers                 # 4 workers, FREE
```

**Smoke test** (Substrate only, no ax). The counter image, the unified trust
bundle, suspend and resume:

```bash
$ATE4 --context agent-substrate create atespace smoke
cat > /tmp/smoke-template.yaml <<EOF
metadata:
  atespace: smoke
  name: counter
containers:
- name: counter
  image: us-central1-docker.pkg.dev/gke-demos-345619/ax/substrate/counter@sha256:58120d883dc9dd16fc9fdd9b5d4959bd780b7df6390b9e04957b5d444d468daf
  command: [/ko-app/counter, --extra-port=9090, --tcp-port=9091]
  wakeupProbe: {httpGet: {path: /readyz, port: 80}}
  env:
  - {name: SSL_CERT_FILE, value: /run/ate/trust-bundle.pem}
  volumeMounts:
  - {name: data, mountPath: /home/counter}
  - {name: trust, mountPath: /run/ate}
resources:
  limits:
  - {name: cpu, quantity: "1"}
  - {name: memory, quantity: 512Mi}
snapshotConfig:
  onCommit: SNAPSHOT_CONTENT_SCOPE_FULL
  storageLocation: gs://ate-snapshots-gke-demos-345619-agent-substrate-us-central1/smoke/
sandboxConfig: {sandboxClass: SANDBOX_CLASS_GVISOR, configName: gvisor-default}
volumes:
- {name: data, durableDir: {}}
- name: trust
  systemInfo:
    dataSources:
    - trustBundle: {names: [egress-mitm.ate.dev, system-roots.ate.dev], path: trust-bundle.pem}
EOF
$ATE4 --context agent-substrate create actor-template -f /tmp/smoke-template.yaml
$ATE4 --context agent-substrate create actor c1 -a smoke --template counter
$ATE4 --context agent-substrate get actor c1 -a smoke              # RUNNING
$ATE4 --context agent-substrate suspend actor c1 -a smoke
$ATE4 --context agent-substrate get actor c1 -a smoke              # SUSPENDED
$ATE4 --context agent-substrate resume actor c1 -a smoke
$ATE4 --context agent-substrate get actor c1 -a smoke              # RUNNING
$ATE4 --context agent-substrate delete actor c1 -a smoke
```

Rollback: see [Rollback](#rollback).

## Phase 5: consumers (downtime ends)

```bash
# 1. ax-redis: restart it so it leaves $WNODE. This wipes ax state, whose
#    task records point at actors that no longer exist anyway.
$K -n ax-system rollout restart deploy/ax-redis && $K -n ax-system rollout status deploy/ax-redis

# 2. ax-server: the v0.4.0 build from Phase 0.
$K -n ax-system set image deploy/ax-server ax-server=$AX_V4_IMAGE
$K -n ax-system scale deploy/ax-server --replicas=1
$K -n ax-system rollout status deploy/ax-server
$K -n ax-system logs deploy/ax-server --tail=50              # connected to api.ate-system.svc, no TLS/auth errors

# 3. Re-apply ax workspaces and models (from Phase 0), then recreate the demo tasks.
ax --context agent-substrate -a cred-test apply -f <workspace files>

# 4. Other Substrate API consumers pick up the new servicedns trust bundle on restart.
$K -n substrate-scope rollout restart deploy/substrate-scope
$K -n lookout-ax rollout restart deploy/lookout-ax
$K -n gmp-system rollout restart deploy/gmp-operator          # only moves it off $WNODE
```

Verify, end to end:
```bash
$K get pods -A -o wide --field-selector spec.nodeName=$WNODE  # only workers, atelet, GKE DaemonSets
                                                              # (+ kube-dns/konnectivity until GKE moves them)
ax --context agent-substrate -a cred-test get tasks
$ATE4 --context agent-substrate get actors -A
$ATE4 --context agent-substrate get egress-policy <task> -a cred-test   # ax created it
$K -n ate-system logs deploy/atenet-egress -c ext-proc | grep -E 'egress denied|credential' | tail
$K -n substrate-scope logs deploy/substrate-scope --tail=30   # collector lists actors and workers without errors
```

Credential injection: a `cred-test` task that calls `aiplatform.googleapis.com`
with `Authorization: placeholder` gets a 200. A task in another atespace gets
a 403 from the provider.

## Phase 6: after a soak (optional)

- Purge the unusable v0.3.0 snapshots. List first, then delete:
  `gcloud storage ls gs://ate-snapshots-gke-demos-345619-agent-substrate-us-central1/`.
  Deleting them ends the full-fidelity rollback (Postgres restore plus
  snapshots).
- Remove `/var/lib/ateom-gvisor` on the nodes. v0.4.0 uses `/var/lib/ate`.
- Delete `$BAK/atepg-v0.3.0.dump` once rollback is off the table.

## Rollback

A rollback is a fresh v0.3.0 install. It doesn't bring the v0.4.0 state back.

1. Stop ax: `$K -n ax-system scale deploy/ax-server --replicas=0`.
2. From `$V4`: `$K -n ax-workers delete workerpool ax-pool --wait`, then
   `clusters/agent-substrate/install.sh delete ate-system`.
3. From `$V3` (branch `agent-substrate-cluster-v0.3.0`, head `34e9cde8`). This
   builds from source at v0.3.0, as originally:
   ```bash
   clusters/agent-substrate/install.sh                                   # VERSION=v0.3.0-dirty, agentgateway
   ATE_ATENET_DATAPLANE=envoy ATE_EXPERIMENTAL_USE_SDSMINT=true \
     ATE_CREDENTIAL_INJECTION_ENABLED=true clusters/agent-substrate/install.sh deploy atenet
   KO_DOCKER_REPO=us-central1-docker.pkg.dev/gke-demos-345619/ax/substrate \
     hack/run-tool.sh ko apply -f manifests/egress-credential-injection/k8s-credential-provider.yaml
   $K apply -f $BAK/cm-k8s-credential-provider-namespace-policy.yaml
   $K -n ate-system rollout restart deploy/k8s-credential-provider
   $K apply -f clusters/agent-substrate/workerpool.yaml                  # then: patch replicas to 4
   ```
   The v0.3.0 ateom-gvisor digest in that file still resolves.
4. Optional, if the v0.3.0 snapshots weren't purged: restore the database.
   ```bash
   $K -n ate-system scale deploy/ate-api-server --replicas=0
   $K -n ate-system exec -i postgres-0 -c postgres -- pg_restore -U postgres -d atepg --clean --if-exists < $BAK/atepg-v0.3.0.dump
   $K -n ate-system scale deploy/ate-api-server --replicas=2
   ```
   Actors come back, but their ax task records don't: ax-redis was wiped.
5. ax-server back to the v0.3 image:
   `$K -n ax-system set image deploy/ax-server ax-server=us-central1-docker.pkg.dev/gke-demos-345619/ax/ax-server-340c3583cc4a989b584acf55b1619e8e@sha256:cc6db817e87dc6798c47592fa46bbfa70a0f6775f73dbaf1b8e4c7805f6b4087`,
   then scale it to 1, and restart substrate-scope and lookout-ax.

The Phase 1 taint can stay through a rollback, because v0.3.0 workers tolerate
it too.

## Needs a human decision

- **The ax-server v0.4 build** (Phase 0.1). It blocks Phase 2.
- **ax-redis has no persistence.** Moving it off the worker node (Phase 5)
  wipes ax workspaces and models. Either re-apply them, as this runbook does,
  or leave ax-redis on the node until it gets a volume.
- **default-pool has auto-upgrade and auto-repair on**, and the worker node is
  pinned by hostname. Upstream requires auto-upgrade off on worker pools. The
  durable fix is a dedicated one-node worker pool: one machine family, pool
  taint `ate.dev/sandboxClass=gvisor:NoSchedule`, auto-upgrade off, and the
  WorkerPool pinned by a pool label instead of the hostname. That is a
  GKE-level change, not made here.
- **Purging the v0.3.0 snapshot objects** from the bucket (Phase 6).
