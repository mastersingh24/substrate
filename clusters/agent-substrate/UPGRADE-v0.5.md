# agent-substrate: v0.4.0 to v0.5.0

This runbook moves the agent-substrate cluster from branch
`agent-substrate-cluster-v0.4.0` to `agent-substrate-cluster-v0.5.0` with a
**fresh Substrate install**: tear down v0.4.0, then install v0.5.0. Run the
phases in order. Each phase lists how to verify it; [Rollback](#rollback) is
at the end. Same shape as [UPGRADE-v0.4.md](UPGRADE-v0.4.md) (38 min of
downtime last time).

Background and evidence: `v05-upgrade/sizing-install.md` and
`v05-upgrade/sizing-code.md` in the research directory.

## Decision: fresh install

Upstream has no supported path from v0.4: `docs/upgrade.md:11` says "Reinstall"
for any pre-1.0 minor, and #1812 (version label removal) says an install from
v0.4 or earlier can't be upgraded in place. Nothing would survive anyway:

| Concern | Effect |
|---|---|
| Snapshots | Don't restore: new gVisor asset (`gvisor-default` `v3`, nightly 2026-10-10), durable dirs are now fs-checkpointed by runsc (#2455), Snapshot API rewritten (#2289, #2449) |
| Actors / templates in Postgres | v0.4 ActorTemplates read back with an empty `sandboxClass` (#2586); `ACTOR_STATE_PAUSED` deleted (#2620) |
| DaemonSet model | v0.4's `atelet-v0-4-0` (version-label selector) vs v0.5's single `atelet` |
| Postgres auth | Password+cert becomes cert-only (#2266) |

**Lost:** every actor, ActorTemplate, atespace, egress policy and tag, the
v0.4 snapshots (left in GCS for rollback), and the ax task records that point
at them.

**Kept:** namespaces `ate-credentials` (Secret `google-token`,
`token-refresher`), `ax-system`, `ax-workers`, `lookout-ax`,
`substrate-scope`, triage namespaces; the bucket and its IAM; the
`substrate-workers` and `n4-preferred` ComputeClasses; node pools.

**Recreated from backup:** ConfigMap `k8s-credential-provider-namespace-policy`.

## What changes for this cluster

| Change | What to do |
|---|---|
| #2522 ate-system default-deny ingress | `ax-system` and `substrate-scope` need `ate.dev/api-access=true` (**already set** on both as of 2026-10-15; verify in Phase 0). Router :80 stays open to all |
| #2524 DNS allowlist in actors | Names outside the actor's egress policy get REFUSED. Lookout's template lists its hosts; tasks without `egress:` resolve nothing |
| #1812 version label removed | atelet is one DaemonSet with no stock nodeSelector. Our patch pins it to `ate.dev/worker-node=true` nodes (Phase 4 labels existing worker nodes) |
| objectstore-plugin sidecar | atelet requests 100m/256Mi per node now; new image `objectstore-plugin` |
| #2332 WorkerPool `sandboxClasses` | `workerpool.yaml` rewritten; also sets worker `resources` |
| #2314 Postgres StorageClass | `install.sh` sets `ATE_API_POSTGRES_STORAGE_CLASS=dynamic-rwo` (patch dropped) |
| #2424 health probes on :9091 | Stock manifests; nothing to do |
| #2573 router `/statusz` loopback-only | `kubectl -n ate-system port-forward deploy/atenet-router 4040:4040` |
| #2586 SandboxClass string, Snapshot API, PAUSED gone | ax-server, runner and substrate-scope must be the v0.5 builds |
| kubectl-ate | Use `bin/kubectl-ate-v0.5.0`; `-v` is verbosity now, `logs actors` → `logs actor` |

## Images (built from tag v0.5.0, `VERSION=v0.5.0`, linux/amd64)

Repository `us-central1-docker.pkg.dev/gke-demos-345619/ax/substrate`, tag
`v0.5.0`. Built 2026-10-15 with
`VERSION=v0.5.0 go run ./cmd/ate-setup publish release-images --ko-docker-repo <repo>`
(log and list: `v05-upgrade/build-release-images.log`, `v05-upgrade/images-v0.5.0.txt`).

| Image | Digest |
|---|---|
| ateapi | `sha256:ad140e040e4b8b9e6810ac5253846e216ede17ddc0ad6c77a814847702720fe8` |
| atecontroller | `sha256:b71831bfaf3d27eeb886c779dc4207298d2037dafd15ce59d75ce3018e532b41` |
| atelet | `sha256:aa4afa8694e2c07799d342f9612b3dcffad397562ecf8fff94ca05794641baa0` |
| atenet | `sha256:6d39f633e27c6851555be35823e32af5b6453c1742c64c4c668663909e648683` |
| objectstore-plugin (new: atelet + ate-api-server sidecar) | `sha256:f60528b1d221e89f9064c49b787d9fdc34cc95acc3d0da89d1d91ae755964cdb` |
| kubernetes-secrets (credential provider) | `sha256:959fe9e9002d6ee945f4a016a059655c5f5c42d11bf48ed81efdde7369acfd72` |
| podcertcontroller | `sha256:e78999d23bd102b0e12ad5faee5aec83666e2ed072f1612e8f7647790ff3cad5` |
| ateom-gvisor (worker) | `sha256:a5d048d94695043d09c1439c40a5faac2691b9b9aa2a0f978b57b8b49825078a` |
| ateom-microvm | `sha256:64d670e86e9a844bf813f2210b58a78b6995af5bf6574574f4190d6433f7a1e3` |
| envoy-dataplane | `sha256:20e59ffacca9fdf7e41068fd9f307fee7f3de67e8f80546b43becb47077ec596` |
| fake-atelet (benchmarks, unused) | `sha256:4e38d7802a6d0975c82db6a4c38c8c95bcc9a5113cf264e95420de89fe123ad6` |
| fake-workersync (benchmarks, unused) | `sha256:a854984df0a20176014bc3bcdb2efa57815648463337f5c439c7934f5a6221b6` |
| counter (demo) | `sha256:9e4266d86c509c39df41ab55195b5d0750bb6c77d5b968d307e31fc37689267d` |
| egress (demo) | `sha256:64a9e4ef8e9632373b45b7f69e51974b8804aa9d4fc28efb3038fdb4a780cf06` |
| fspersist (demo) | `sha256:e94f44b554f6aad67649f2c094af48a65ee46d3f3a00c2d7216fa24888685edc` |
| sandbox (demo) | `sha256:912e4a7bb0a02c75252c4d916ea01e149f526eb75359ab848b7182046af266e1` |

The router still runs the public `envoyproxy/envoy` image its manifest pins.
The v0.4.0 images (rollback) are in `v04-migration/images-v0.4.0.txt` and in
UPGRADE-v0.4.md on the v0.4 branch.

## Expected downtime

Phase 2 through Phase 6: **45 to 60 minutes** (teardown ~5 min, install
10–15 min including a new 500Gi PD, atelet/workers ~5 min if the N4 node
exists, consumers and smoke test ~15 min).

## Conventions

```bash
E=/home/user/projects/research/ax-substrate-eval
V4=$E/substrate-v0.4      # branch agent-substrate-cluster-v0.4.0 (live install)
V5=$E/substrate-v0.5      # branch agent-substrate-cluster-v0.5.0
BAK=$E/v05-upgrade/backup-v0.4.0
ATE4="$E/bin/kubectl-ate-v0.4.0 --context agent-substrate"
ATE5="$E/bin/kubectl-ate-v0.5.0 --context agent-substrate"
AX4="$E/bin/ax-v04 --context agent-substrate"
AX5="$E/bin/ax-v05 --context agent-substrate"    # fork CLI built from the ax v0.5 port (Phase 0.1)
K="kubectl --context agent-substrate"
R=us-central1-docker.pkg.dev/gke-demos-345619/ax/substrate
```

`$ATE5` was built from the v0.5.0 checkout: `go build -o $E/bin/kubectl-ate-v0.5.0 ./cmd/kubectl-ate`;
`ate-selector` likewise: `go build -o $E/bin/ate-selector-v0.5.0 ./hack/ate-selector`.

## Phase 0: prerequisites and backups (no downtime)

1. **Client builds for v0.5 exist** (don't start Phase 2 without all of them):
   - ax-server built against `github.com/agent-substrate/substrate v0.5.0`
     (SandboxClass string, Snapshot API / fidelity, no PAUSED), manifest staged at
     `$E/deploy/ax-server.v05.yaml`. Write the image down as `AX_V5_IMAGE`.
   - The ax task runner inside the mast-triage image rebuilt for v0.5, and the
     lookout template `$E/lookout-ax/task-template.v05.yaml` pointing at it.
   - substrate-scope: draft PR `feat/substrate-v0.5` (go-steer/substrate-scope
     #21), merged at cutover; CI deploys `main`.
   - The fork ax CLI for v0.5 at `$E/bin/ax-v05`.

2. **The v0.5.0 images resolve to the digests above.**
   ```bash
   for i in ateapi atecontroller atelet atenet objectstore-plugin kubernetes-secrets podcertcontroller ateom-gvisor envoy-dataplane; do
     echo "$i $(crane digest $R/$i:v0.5.0)"; done
   ```

3. **The v0.5 branch is what you think it is.**
   ```bash
   cd $V5 && git status --short && git log --oneline -3   # clean; head = agent-substrate-cluster-v0.5.0
   grep -n "worker-node\|compute-class" manifests/ate-install/atelet.yaml
   grep -n "parked-request-budget\|terminationGracePeriodSeconds: 120" manifests/ate-install/atenet-router.yaml
   grep -n "workerImage" clusters/agent-substrate/workerpool*.yaml           # ateom-gvisor digest = the table above
   ```

4. **Namespace labels** (harmless on v0.4; already present 2026-10-15):
   ```bash
   $K get ns ax-system substrate-scope -L ate.dev/api-access     # both "true"
   # if not: $K label ns ax-system substrate-scope ate.dev/api-access=true
   ```

5. **Backups** into `$BAK` (read-only against the cluster):
   ```bash
   mkdir -p $BAK && cd $BAK
   # Substrate objects (unusable on v0.5, for the record and for rollback)
   $ATE4 get actors -A -o yaml          > substrate-actors.yaml
   $ATE4 get actor-templates -A -o yaml > substrate-actor-templates.yaml
   $ATE4 get workers -o yaml            > substrate-workers.yaml
   $ATE4 get atespaces -o yaml          > substrate-atespaces.yaml
   # Per-actor egress policies
   $ATE4 get actors -A -o yaml | python3 -c 'import sys,yaml; [print(a["metadata"]["atespace"], a["metadata"]["name"]) for a in yaml.safe_load(sys.stdin).get("actors",[])]' |
     while read a n; do $ATE4 get egress-policy "$n" -a "$a" -o yaml > "egress-$a-$n.yaml" 2>/dev/null; done
   # ax: tasks, workspaces, models (ax-redis has no volume; it is wiped in Phase 6)
   for a in default cred-test; do
     $AX4 -a $a get tasks > ax-tasks-$a.txt
     for t in $(awk 'NR>1{print $1}' ax-tasks-$a.txt); do $AX4 -a $a get task $t > ax-task-$a-$t.yaml; done
     $AX4 -a $a get workspaces > ax-workspaces-$a.txt; $AX4 -a $a get models > ax-models-$a.txt
     for w in $(awk 'NR>1{print $1}' ax-workspaces-$a.txt); do $AX4 -a $a describe workspace $w > ax-workspace-$a-$w.txt; done
   done
   # Credential provider namespace grant (re-applied in Phase 5)
   $K -n ate-system get cm k8s-credential-provider-namespace-policy -o yaml > cm-k8s-credential-provider-namespace-policy.yaml
   # Kubernetes objects
   $K get workerpool -A -o yaml > workerpools.yaml
   $K get computeclass substrate-workers -o yaml > computeclass-substrate-workers.yaml
   $K get nodes -L cloud.google.com/compute-class,node.kubernetes.io/instance-type,ate.dev/substrate-version > nodes.txt
   for ns in ate-system ax-system ax-workers ate-credentials lookout-ax substrate-scope; do
     $K -n $ns get deploy,sts,ds,svc,cm,netpol,sa -o yaml > k8s-$ns.yaml; done
   $K -n ate-system get deploy,sts,ds -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[*].image}{"\n"}{end}' > substrate-images.txt
   # Optional: the v0.4 database (rollback with full state + the v0.4 snapshots)
   $K -n ate-system exec postgres-0 -c postgres -- pg_dump -U postgres -Fc atepg > atepg-v0.4.0.dump
   ```
   Check: `ls -la $BAK`, the cm file contains `atespace: cred-test`, and the
   ax task files are YAML specs (not tables).

6. **Kept objects are healthy:**
   `$K -n ate-credentials get secret google-token && $K -n ate-credentials get deploy token-refresher`.

## Phase 1: stop the consumers (downtime starts)

```bash
$K -n lookout-ax scale deploy/lookout-ax --replicas=0
$K -n ax-system scale deploy/ax-server --replicas=0
$K -n ax-system get cronjob task-reaper -o jsonpath='{.spec.suspend}'   # keep true
```

## Phase 2: tear down v0.4.0

From the **v0.4 checkout**: its manifests match what is installed, and its
delete removes the `ate.dev/substrate-version` node labels (v0.5's no longer
does).

```bash
cd $V4 && git status --short    # must be clean, branch agent-substrate-cluster-v0.4.0

# 1. The pool first, while ate-controller is up, so it deletes its
#    Deployment and NetworkPolicy itself.
$K -n ax-workers delete workerpool ax-pool --wait
$K -n ax-workers get deploy,pods,networkpolicy            # nothing from ax-pool

# 2. ate-system, podcertificate-controller-system, CRDs, cluster RBAC, node
#    labels. The v0.4 installer owns the credential provider, so it goes too.
clusters/agent-substrate/install.sh delete ate-system
```

Verify:
```bash
$K get ns ate-system podcertificate-controller-system   # NotFound
$K get crd | grep ate.dev                               # nothing
$K get nodes -L ate.dev/substrate-version               # column empty
$K get pv | grep ate-system                             # nothing
$K get clusterrole,clusterrolebinding -o name | grep -E 'ate-|atelet|podcert|credential-provider'   # nothing
$K -n ate-credentials get secret google-token           # still there
```

## Phase 3: install v0.5.0

```bash
cd $V5 && git status --short    # clean, branch agent-substrate-cluster-v0.5.0

# Prebuilt v0.5.0 images, ATE_API_POSTGRES_STORAGE_CLASS=dynamic-rwo,
# ATE_CREDENTIAL_PROVIDER={"name":"k8s.io"}, Envoy dataplane, default ACTOR_JWT_ISSUER.
clusters/agent-substrate/install.sh 2>&1 | tee $E/v05-upgrade/install-v0.5.log
```

Verify:
```bash
$K -n ate-system get pods -o wide                     # all Running (atelet: none yet, see Phase 4)
$K -n ate-system get netpol                           # default-deny-ingress, ate-api-server, postgres, atelet,
                                                      # atenet-router, atenet-egress, ate-system-observability, k8s-credential-provider
$K -n ate-system get pvc                              # data-postgres-0 Bound, STORAGECLASS dynamic-rwo
$K -n ate-system get pod postgres-0 atenet-egress-* -o wide 2>/dev/null; $K -n ate-system get pods -l 'app in (postgres,atenet-egress)' -o wide   # on n4-preferred nodes
$K -n ate-system get secret ate-api-server-envvars -o jsonpath='{.data.ATE_API_ACTOR_JWT_ISSUER}' | base64 -d; echo   # https://idp.ate-system.svc
$K -n ate-system get deploy,sts,ds -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[*].image}{"\n"}{end}'   # digests match the table
$K get sandboxconfig gvisor-default -o jsonpath='{.spec.defaultVersion} {.metadata.annotations}'; echo   # v3, is-class-default "true"
$K -n ate-system get ds atelet -o jsonpath='{.spec.template.spec.nodeSelector}{"\n"}{.spec.template.spec.tolerations}{"\n"}'
ls ~/.cache/ate-setup/installs/                       # the v0.5 record (has cluster.substrateVersion): keep it
```

## Phase 4: atelet and workers

```bash
# 1. ComputeClass: now stamps ate.dev/worker-node=true (was ate.dev/substrate-version).
#    Unverified whether GKE relabels nodes of pools it already created, so
#    label existing class nodes by hand too.
$K apply -f clusters/agent-substrate/computeclass-substrate-workers.yaml
$K get computeclass substrate-workers                 # Health=True
$K label node -l cloud.google.com/compute-class=substrate-workers ate.dev/worker-node=true --overwrite

# 2. atelet lands on the worker nodes only.
$K -n ate-system rollout status ds/atelet --timeout=300s

# 3. The pool: 4 replicas, sandboxClasses [gvisor], v0.5.0 ateom-gvisor by digest,
#    resources requests 300m/384Mi, limits 500m/1Gi.
$K apply -f clusters/agent-substrate/workerpool.yaml
$K -n ax-workers get workerpool ax-pool -o jsonpath='{.status}'; echo   # readyReplicas 4, sandboxClasses[0].configRef gvisor-default, Resolved=True
$K -n ax-workers get pods -o wide                     # 4 Running on the substrate-workers node(s)
$ATE5 get workers                                     # 4 workers; capacity 500m / 1Gi each
```

If no worker node exists and N4 and C4 are both out of stock, the workers stay
Pending (`whenUnsatisfiable: DoNotScaleUp`). Fall back to
`workerpool-hostname.yaml` (label that node `ate.dev/worker-node=true` first).

If the 4 workers don't fit on one n4-highcpu-2 (one stays Pending and GKE adds
a second node), that's the requests in `workerpool.yaml`; lower them, or accept
a second node.

**Smoke test** (Substrate only, no ax). v0.5 changes from the v0.4 version:
`sandboxClass: gvisor` (string), `preferredFidelity` instead of `onCommit`, and
the counter's egress policy isn't needed (no outbound calls).

```bash
$ATE5 create atespace smoke
cat > /tmp/smoke-template.yaml <<EOF
metadata:
  atespace: smoke
  name: counter
containers:
- name: counter
  image: $R/counter:v0.5.0@sha256:9e4266d86c509c39df41ab55195b5d0750bb6c77d5b968d307e31fc37689267d
  command: [/ko-app/counter, --extra-port=9090, --tcp-port=9091]
  wakeupProbe: {httpGet: {path: /readyz, port: 80}}
  volumeMounts:
  - {name: data, mountPath: /home/counter}
resources:
  limits:
  - {name: cpu, quantity: 250m}
  - {name: memory, quantity: 256Mi}
snapshotConfig:
  preferredFidelity: SNAPSHOT_FIDELITY_MEMORY
  storageLocation: gs://ate-snapshots-gke-demos-345619-agent-substrate-us-central1/smoke/
sandboxConfig: {sandboxClass: gvisor, configName: gvisor-default}
volumes:
- {name: data, durableDir: {}}
EOF
# Field names follow demos/counter/counter-template.yaml.tmpl at v0.5.0.
$ATE5 create actor-template -f /tmp/smoke-template.yaml
$ATE5 create actor c1 -a smoke --template counter
$ATE5 resume actor c1 -a smoke && $ATE5 get actor c1 -a smoke     # RUNNING
$ATE5 suspend actor c1 -a smoke && $ATE5 get actor c1 -a smoke    # SUSPENDED, status.snapshots[] has one entry
$ATE5 resume actor c1 -a smoke && $ATE5 get actor c1 -a smoke     # RUNNING
$ATE5 logs actor c1 -a smoke | tail                               # note: "logs actor", not "logs actors"
$ATE5 suspend actor c1 -a smoke && $ATE5 delete actor c1 -a smoke
```

## Phase 5: credential provider namespace policy

The installer creates the ConfigMap empty; the provider reads it at startup.

```bash
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
diff <($K -n ate-system get cm k8s-credential-provider-namespace-policy -o jsonpath='{.data}') \
     <(python3 -c 'import yaml,json,sys; print(json.dumps(yaml.safe_load(open(sys.argv[1]))["data"],separators=(",",":")))' $BAK/cm-k8s-credential-provider-namespace-policy.yaml) && echo same
```

## Phase 6: consumers (downtime ends)

```bash
# 1. ax-redis restart wipes ax state (its task records point at deleted actors).
$K -n ax-system rollout restart deploy/ax-redis && $K -n ax-system rollout status deploy/ax-redis

# 2. ax-server v0.5 (manifest staged by the ax port; check the image is AX_V5_IMAGE).
grep -n "image:" $E/deploy/ax-server.v05.yaml
$K apply -f $E/deploy/ax-server.v05.yaml
$K -n ax-system scale deploy/ax-server --replicas=1
$K -n ax-system rollout status deploy/ax-server
$K -n ax-system logs deploy/ax-server --tail=50        # connected to api.ate-system.svc:443; no timeouts (= namespace label OK)

# 3. Workspaces and models from $BAK, e.g. the gke-demo workspace.
$AX5 -a cred-test apply -f $E/lookout-ax/workspace.yaml

# 4. substrate-scope v0.5: mark PR #21 ready and merge; CI deploys main.
gh pr ready 21 -R go-steer/substrate-scope && gh pr merge 21 -R go-steer/substrate-scope --squash
$K -n substrate-scope rollout status deploy/substrate-scope
$K -n substrate-scope logs deploy/substrate-scope --tail=30   # lists actors and workers, no PermissionDenied/timeouts

# 5. lookout with the v0.5 task template (keep the v0.4 one as task-template.v04.yaml).
cd $E/lookout-ax && cp task-template.v05.yaml task-template.yaml && ./setup.sh
$K -n lookout-ax scale deploy/lookout-ax --replicas=1
$K -n lookout-ax rollout restart deploy/lookout-ax && $K -n lookout-ax rollout status deploy/lookout-ax

# 6. ax-system/cred-curl (test helper) if it was lost: recreate as in v0.4.
$K -n ax-system get pod cred-curl
```

## Phase 7: verification

Tests a–h from the v0.4 upgrade (results in `substrate-v0.4-migration.md`,
"Test results"):

| Test | How | Pass |
|---|---|---|
| a. lookout incident → ax task → mast diagnosis | `$E/demo-break.sh` (break a triage-demo workload), then `$AX5 -a cred-test get tasks` | task `lookout-<hash>` Running within seconds; `$ATE5 get egress-policy <task> -a cred-test` lists aiplatform + container.googleapis.com with replaceHeaders; mast posts a diagnosis. `$E/demo-break.sh restore` afterwards |
| b. idle suspend | wait 10 min | ax condition `IdleSuspended` |
| c. router wake, no restart (MEMORY fidelity) | `$K -n ax-system exec cred-curl -- curl -sS -m 90 -w ' %{http_code} %{time_total}s\n' -H "ate-target-actor: cred-test/<task>" -H "Authorization: Bearer $(cat $E/triage/attach-token)" http://atenet-router.ate-system.svc.cluster.local/sessions` | 200; ax `ResumedByRequest`; mast PID/start tick unchanged (`$AX5 -a cred-test ssh <task> -- cat /proc/uptime`) |
| d. re-suspend | wait 10 min | `IdleSuspended` again |
| e. session reuse | re-fire the same incident | same session, one short turn |
| f. substrate-scope live view | open the scope UI; `/config` 200; WebSocket 101 | 4 workers with IPs and node; actors listed; snapshots show `status.snapshots` locality |
| g. resource limits | a task with `resources.limits: {cpu: 250m, memory: 512Mi}` | template carries the limits; `$ATE5 get workers` shows 250m/500m allocated on one worker |
| h. MEMORY vs VOLUMES snapshots | suspend/resume an idle mast task with each fidelity (`AX_SNAPSHOT_SCOPE`) | record sizes and timings |

New checks for v0.5:

```bash
# i. Namespace labels and API reachability
$K get ns -L ate.dev/api-access | grep -E 'ax-system|substrate-scope'          # true
$K -n ax-system logs deploy/ax-server --since=10m | grep -iE 'deadline|unavailable|i/o timeout' | head   # nothing
$K -n lookout-ax run api-probe --rm -i --restart=Never --image=curlimages/curl -- \
  curl -sk -m 5 -o /dev/null -w '%{http_code}\n' https://api.ate-system.svc:443/ || echo "blocked (expected: lookout-ax has no label)"

# j. Router plain HTTP still reachable from lookout-ax, substrate-scope, ax-system
for ns in lookout-ax substrate-scope ax-system; do
  $K -n $ns run router-probe --rm -i --restart=Never --image=curlimages/curl -- \
    curl -sS -m 10 -o /dev/null -w "$ns %{http_code}\n" http://atenet-router.ate-system.svc.cluster.local/
done   # an HTTP status (e.g. 400/404 without ate-target-actor), not a timeout

# k. DNS allowlist inside an actor (a running lookout task; egress lists the googleapis hosts)
$AX5 -a cred-test ssh <task> -- getent hosts aiplatform.googleapis.com    # resolves
$AX5 -a cred-test ssh <task> -- getent hosts example.com                  # fails (REFUSED)
$AX5 -a cred-test ssh <task> -- getent hosts kubernetes.default.svc       # fails: in-cluster names are not allowed either

# l. atelet only on worker nodes; e2-medium nodes not loaded by it
$K -n ate-system get pods -l app=atelet -o wide                 # only substrate-workers nodes
$K get nodes -l ate.dev/worker-node=true                        # same set
$K describe node -l cloud.google.com/gke-nodepool=default-pool | grep -A3 'Allocated resources'

# m. Health on :9091, router /statusz loopback-only
$K -n ate-system port-forward deploy/atenet-router 4040:4040 &  sleep 2; curl -s localhost:4040/statusz | head; kill %1

# n. Cold wake after a long suspend (parked-request budget 60s)
#    after a task has been suspended for > 1 h, test c again: 200 (not 504), even if > 10 s.
```

**o. N4↔C4 MEMORY restore re-test** (new gVisor and fs-checkpoint format; the
2026-10-11 result was on the old runsc). Needs a temporary C4 pool; creating
it is a GKE change for a human:

```bash
gcloud container node-pools create c4-snaptest \
  --cluster agent-substrate --region us-central1 --project gke-demos-345619 \
  --machine-type c4-standard-2 --num-nodes 1 --node-locations us-central1-c \
  --node-labels ate.dev/worker-node=true,ate.dev/snaptest=c4 \
  --node-taints ate.dev/sandboxClass=gvisor:NoSchedule \
  --disk-type hyperdisk-balanced --disk-size 50 --no-enable-autoupgrade --quiet
```

`ate.dev/worker-node=true` replaces v0.4's `ate.dev/substrate-version` label:
without it atelet doesn't run there. Then run a copy of
`$E/v04-migration/snaptest-c4.sh` adapted for v0.5:
- `ATE=$E/bin/kubectl-ate-v0.5.0`, `AX=$E/bin/ax-v05`, `SEL=$E/bin/ate-selector-v0.5.0`;
- the temporary WorkerPool `c4-test` uses `sandboxClasses: [{name: gvisor}]`
  and the v0.5.0 ateom-gvisor digest (no `sandboxClass`);
- check `state()`'s awk columns against `$ATE5 get actors -A` output;
- the actor must use MEMORY fidelity (formerly FULL).
Pass: N4→C4 and C4→N4 resumes with mast not restarted. Delete the pool after:
`gcloud container node-pools delete c4-snaptest --cluster agent-substrate --region us-central1 --project gke-demos-345619 --quiet`.

## Phase 8: after a soak (optional)

- Remove the leftover `ate.dev/sandboxClass=gvisor:NoSchedule` taint on
  default-pool node `6v23`: `$K taint node gke-agent-substrate-default-pool-447e9856-6v23 ate.dev/sandboxClass-`.
- Purge v0.3/v0.4 snapshot prefixes in the bucket (ends the full-fidelity rollback).
- Delete `$BAK/atepg-v0.4.0.dump` once rollback is off the table.

## Rollback

A rollback is a fresh v0.4.0 install; it doesn't bring v0.5 state back.

1. Stop consumers: `$K -n lookout-ax scale deploy/lookout-ax --replicas=0; $K -n ax-system scale deploy/ax-server --replicas=0`.
2. From `$V5`: `$K -n ax-workers delete workerpool ax-pool --wait`, then
   `clusters/agent-substrate/install.sh delete ate-system`.
3. ComputeClass back to the v0.4 label (atelet-v0-4-0 selects
   `ate.dev/substrate-version=v0.4.0`):
   `$K apply -f $BAK/computeclass-substrate-workers.yaml` (or the file on the
   v0.4 branch), and `$K label node -l cloud.google.com/compute-class=substrate-workers ate.dev/substrate-version=v0.4.0 --overwrite`.
4. From `$V4` (branch `agent-substrate-cluster-v0.4.0`, head `fce319a9`):
   ```bash
   clusters/agent-substrate/install.sh                    # v0.4.0 images (v04-migration/images-v0.4.0.txt)
   $K apply -f $BAK/cm-k8s-credential-provider-namespace-policy.yaml
   $K -n ate-system rollout restart deploy/k8s-credential-provider
   $K apply -f clusters/agent-substrate/workerpool.yaml
   ```
5. Optional, with the v0.4 snapshots still in the bucket: restore the database.
   ```bash
   $K -n ate-system scale deploy/ate-api-server --replicas=0
   $K -n ate-system exec -i postgres-0 -c postgres -- pg_restore -U postgres -d atepg --clean --if-exists < $BAK/atepg-v0.4.0.dump
   $K -n ate-system scale deploy/ate-api-server --replicas=2
   ```
6. Consumers back to v0.4: `$K apply -f $E/deploy/ax-server.v04.resolved.yaml`
   (scale to 1); lookout `task-template.v04.yaml` + `setup.sh`; revert the
   substrate-scope merge on main (CI redeploys) or apply
   `$E/v04-migration/substrate-scope.v04.yaml`. Recreate tasks from `$BAK`.
7. The `ate.dev/api-access` namespace labels and the `ate.dev/worker-node`
   node labels are harmless on v0.4; leave them.

## Needs a human decision

- **Go for cutover** (shared cluster change; Phases 1–6).
- **Client builds** (Phase 0.1) block Phase 1.
- **Worker resources** in `workerpool.yaml` (300m/384Mi requests, 500m/1Gi
  limits): the memory limit is a hard cgroup cap shared by every actor on a
  worker. Raise it, or drop `resources` to keep v0.4 behavior (each worker
  advertises the whole node).
- **C4 test pool** for check o (GKE node-pool change).
- **Purging** old snapshots (Phase 8).
