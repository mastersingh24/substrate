# agent-substrate cluster (gke-demos-345619, us-central1)

This branch is Agent Substrate `v0.3.0` plus the changes needed to run it on
this cluster, where ax is being evaluated. The cluster was installed fresh from
this source on 2026-10-06, with images built by ko.

## Changes from v0.3.0

- `manifests/ate-install/postgres/postgres.yaml`
  - `storageClassName: dynamic-rwo`. Without it the claim gets `standard-rwo`
    (pd-balanced), which can't attach to the C4 nodes the cluster autoscaler
    creates: `Error 400: pd-balanced disk type cannot be used by c4-highcpu-4
    machine type`. Reported upstream as agent-substrate/substrate#2298.
  - `nodeSelector: cloud.google.com/compute-class: n4-preferred`. Postgres
    requests 2 CPU, which the default pool's e2-medium nodes can't fit. This
    one is specific to this cluster and isn't proposed upstream.
- `clusters/agent-substrate/`: this directory.

## Install and operate

```sh
clusters/agent-substrate/install.sh                         # deploy or re-apply ate-system
clusters/agent-substrate/install.sh publish worker-images   # rebuild ateom images
kubectl --context agent-substrate apply -f clusters/agent-substrate/workerpool.yaml
```

The script pins the version label to `v0.3.0-dirty`, the value the cluster got
on first install. Changing it makes ate-setup add a second atelet DaemonSet,
as in a rolling upgrade.

- Uninstall: `install.sh delete ate-system`.
- Kubeconfig context: `agent-substrate`.
- Images: `us-central1-docker.pkg.dev/gke-demos-345619/ax/substrate`.
- Snapshot bucket: `gs://ate-snapshots-gke-demos-345619-agent-substrate-us-central1`.
  ate-api-server and atelet already have `objectAdmin` and `bucketViewer` on it.
- Egress dataplane: `agentgateway`.

## Credential injection (keeps model keys out of actors)

Working on this cluster since 2026-10-07. The egress gateway swaps a
placeholder header for the real key, so the key is never in the ActorTemplate,
the sandbox or its snapshots.

- **Gateway:** `ATE_ATENET_DATAPLANE=envoy ATE_EXPERIMENTAL_USE_SDSMINT=true
  ATE_CREDENTIAL_INJECTION_ENABLED=true install.sh deploy atenet`. The sdsmint
  gateway is scheduled on the `n4-preferred` compute class (its sidecar doesn't
  fit e2-medium).
- **Provider:** `manifests/egress-credential-injection/k8s-credential-provider.yaml`
  (built with ko), plus a namespace policy ConfigMap mapping atespaces to the
  namespaces whose Secrets they may use.
- **Actor:** a `systemInfo` volume with the `egress-mitm.ate.dev` trust bundle,
  and `SSL_CERT_FILE` and `SSL_CERT_DIR` pointing at it.
- **Policy:** an `https` rule with
  `effects.replaceHeaders: [{header: x-goog-api-key, credentialUri: ate-secret://k8s.io/default/<ns>/<secret>/<key>}]`.
  The actor sends `x-goog-api-key: placeholder`.

With the sdsmint gateway, every HTTPS connection is intercepted, so an actor
without the trust bundle can't do TLS. ax-created tasks don't get the bundle
(ax can't add volumes).

## Things to know on this version

- Egress is default-deny per actor. Each actor needs an egress policy
  (`egress-policy-example.yaml`). ax doesn't create them (google/ax#449).
- The router routes by the `ate-target-actor` header (ax `main` matches). The
  10-second route timeout from v0.1.0-gke.1 is gone.
- Suspend sends no SIGTERM. On resume the runner comes back from the golden
  snapshot and the task command starts again. Only `/workspace` survives
  (google/ax#451).
- Reference task images by digest. A tag makes template creation fail with
  "actor template not found" (google/ax#366).
- Keep workers on one CPU type. Restoring a snapshot taken on an AMD host onto
  an Intel host fails with `incompatible FeatureSet`.
