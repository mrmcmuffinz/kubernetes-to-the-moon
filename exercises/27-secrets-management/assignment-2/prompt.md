# Assignment Prompt: Secrets Management — Assignment 2

**Series:** Secrets Management (2 of 2)
**Topic slug:** secrets-management
**Topic directory:** exercises/27-secrets-management/assignment-2/

## Metadata

**Domain:** CKS — Minimize Microservice Vulnerabilities (20%)
**Competencies:** External Secrets Operator, SecretStore/ExternalSecret resources, Vault basics, secret rotation
**Prerequisites:** secrets-management/assignment-1, 12-rbac/assignment-1

## Scope — In Scope

*External Secrets Operator (ESO) architecture*
- What ESO is: a Kubernetes operator that syncs secrets from external providers into Kubernetes Secrets
- The three main CRDs: SecretStore (namespace-scoped connection config), ClusterSecretStore (cluster-scoped), ExternalSecret (the sync mapping)
- The sync controller: watches ExternalSecret resources, fetches from the provider, creates/updates the target Kubernetes Secret
- Installing ESO: kubectl apply or Helm chart

*SecretStore configuration*
- spec.provider: the external provider type (aws, vault, gcpsm, fake)
- The fake provider: ESO's built-in fake provider for local testing without a real external system
  - spec.provider.fake.data: list of {key, value} pairs the fake provider returns
- Authentication to the provider: varies by provider (for fake: no auth needed)
- Namespace scope of SecretStore vs ClusterSecretStore

*ExternalSecret resource*
- spec.secretStoreRef.name and .kind: pointing to the SecretStore to use
- spec.target.name: the name of the Kubernetes Secret to create
- spec.target.creationPolicy: Owner (ESO owns the Secret), Merge, None
- spec.refreshInterval: how often ESO re-syncs from the provider (e.g., 1h, 5m)
- spec.data: list of {secretKey (key in the K8s Secret), remoteRef.key (key in the external store)}
- spec.dataFrom: bulk sync all keys from a remote path
- Verifying the sync: kubectl get secret <target-name> and checking the synced values

*Using the fake provider for exercises*
- Creating a SecretStore with provider: fake and a list of key-value data entries
- Creating an ExternalSecret pointing to the fake store
- Verifying the Kubernetes Secret is created with the correct values
- Simulating a secret update: updating the fake provider data and observing the re-sync

*HashiCorp Vault basics for Kubernetes*
- Vault architecture in brief: server, secrets engines (KV v2), auth methods
- Running Vault in dev mode as a pod in kind: vault server -dev -dev-root-token-id=root
- The KV v2 secrets engine: vault kv put secret/myapp/config db-password=secret, vault kv get
- Kubernetes auth method: Vault validates the pod service account JWT to authenticate
- vault agent injector: annotation-based sidecar that injects secrets into pods as files
  - vault.hashicorp.com/agent-inject: "true"
  - vault.hashicorp.com/agent-inject-secret-config: "secret/data/myapp/config"
  - vault.hashicorp.com/role: the Vault role to use
- Verifying injected secrets: kubectl exec into pod and cat the injected file

*Secret rotation patterns*
- refreshInterval in ExternalSecret: automatic re-sync when the external value changes
- Rolling pods after a secret changes: using a Deployment annotation to trigger rollout on Secret change
- Immutable Secrets with versioned names: Secret v1, v2, v3 instead of updating in place — pods reference the versioned name, rollout changes the reference
- The Kubernetes Secret lastUpdateTime: checking when a Secret was last updated

## Scope — Out of Scope

- etcd encryption at rest: covered in secrets-management/assignment-1
- Vault production setup (HA, storage backends): out of scope
- AWS Secrets Manager / GCP Secret Manager as ESO providers: conceptual mention only, exercises use fake provider
- CSI secrets driver: out of scope

## Environment

Single-node kind cluster. ESO installed via kubectl apply or Helm. For Vault exercises, run Vault as a pod in dev mode within the kind cluster (using the official Vault container image). The tutorial must document all installation steps.

## Resource Gate

All Kubernetes resources are in scope.

## Topic-specific Conventions

- All exercises using the fake provider must be self-contained: the SecretStore with fake data and the ExternalSecret both defined in the exercise setup.
- Vault exercises use dev mode (vault server -dev) for simplicity — clearly note this is not production Vault.
- Tutorial namespace: `tutorial-secrets-management`.

## Exercise Distribution

- Level 1: Create a SecretStore with the fake provider, create an ExternalSecret, verify the Kubernetes Secret is created with the correct values
- Level 2: Update the fake provider data, trigger a re-sync, verify the Kubernetes Secret is updated; configure Vault dev mode and store a secret
- Level 3 (debugging): Bare headings. Broken ESO setups (ExternalSecret referencing a non-existent SecretStore key, wrong secretStoreRef kind, target Secret not created because ESO lacks RBAC)
- Level 4: Full ESO workflow with Vault — install Vault, configure Kubernetes auth, create a SecretStore pointing to Vault KV, sync a secret to a Kubernetes Secret, mount it in a pod
- Level 5 (debugging): An application pod is failing because its secret is stale (external value changed but Kubernetes Secret was not re-synced); diagnose the ESO sync status and fix the refreshInterval configuration
