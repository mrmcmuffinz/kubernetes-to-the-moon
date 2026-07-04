# Secrets Management

**Topic area:** Kubernetes secrets security and external secret stores
**Certification relevance:** CKS (Minimize Microservice Vulnerabilities 20%)
**Assignments in this topic:** 2

---

## Why Two Assignments

Secrets management in Kubernetes has two distinct layers. The first is hardening how Kubernetes itself stores and protects secrets: encrypting the etcd data store so secrets are not stored in plaintext, and being deliberate about how secrets are exposed to pods (env vars vs volumes). The second is integrating external secret stores: the External Secrets Operator for pulling secrets from external providers, and HashiCorp Vault basics for Kubernetes. These two layers require different tools and represent different points on the security maturity curve.

---

## Assignment Summary

| Assignment | Focus | Prerequisites |
|---|---|---|
| assignment-1 | etcd encryption at rest, EncryptionConfiguration, verifying ciphertext, secret exposure patterns (env vs volume) | 17-cluster-lifecycle/assignment-3, 01-pods/assignment-2 |
| assignment-2 | External Secrets Operator, SecretStore and ExternalSecret resources, HashiCorp Vault basics for Kubernetes, secret rotation | secrets-management/assignment-1 |

---

## Assignment 1: etcd Encryption and Secret Exposure

Subtopics:
- *etcd plaintext problem:* using etcdctl to read a secret from etcd without encryption (demonstrating the risk), understanding that base64 in a Kubernetes Secret is encoding not encryption
- *EncryptionConfiguration resource:* providers list (aescbc, secretbox, identity), keys with name and secret fields, the order of providers (first for write, all for read)
- *Enabling encryption:* adding --encryption-provider-config to the kube-apiserver static pod manifest, mounting the config file, verifying the API server restarts cleanly
- *Verifying encryption:* using etcdctl get to read a secret key and confirm it is ciphertext (not plaintext), kubectl get secret to confirm Kubernetes still decrypts correctly
- *Key rotation:* updating EncryptionConfiguration to add a new key, re-encrypting existing secrets with kubectl get secrets --all-namespaces -o json | kubectl replace -f -
- *Secret exposure patterns:* env var exposure (visible in ps, /proc/PID/environ, pod describe) vs volume mount exposure (file only, not in environment), using secretKeyRef vs volumeMount, why volume mounts are preferred for sensitive values
- *Automounting controls:* automountServiceAccountToken: false reviewed as a secret exposure reduction

---

## Assignment 2: External Secrets and Vault

Subtopics:
- *External Secrets Operator architecture:* SecretStore and ClusterSecretStore (the connection to the external provider), ExternalSecret (the mapping from external keys to Kubernetes Secret fields), the sync controller
- *SecretStore configuration:* provider field (aws, vault, gcpsm, azurekv, fake for testing), authentication to the provider, namespaced vs cluster-scoped stores
- *ExternalSecret resource:* spec.secretStoreRef, spec.target.name (the Kubernetes Secret to create), spec.data (mapping external key paths to Secret keys), spec.refreshInterval
- *Using the fake provider for exercises:* the ESO fake provider for local testing without a real external system, creating a SecretStore with provider: fake, demonstrating the sync workflow
- *HashiCorp Vault basics:* Vault architecture (server, secrets engine, auth methods), KV v2 secrets engine, Kubernetes auth method (Vault reads the pod service account token to authenticate), vault agent injector pattern (annotation-based sidecar injection)
- *Secret rotation patterns:* refreshInterval in ExternalSecret for automatic re-sync, rolling pods after a secret changes, using immutable Secrets with versioned names

---

## Scope Boundaries

**Not covered:**
- etcd backup and restore: covered in 17-cluster-lifecycle/assignment-3
- Service account tokens (general): covered in 12-rbac
- Pod security contexts: covered in 13-security-contexts
- RBAC for secret access: covered in 12-rbac

---

## Cluster Requirements

Assignment-1 requires access to edit the kube-apiserver static pod manifest and run etcdctl against the kind cluster etcd. The tutorial must document installing etcdctl and connecting to the kind cluster etcd endpoint. Assignment-2 requires the External Secrets Operator installed in the cluster. A Vault server can be run as a pod in the kind cluster for the Vault exercises (using the official Vault Helm chart in dev mode).

---

## Recommended Order

Assignment-1 before assignment-2. Understanding how Kubernetes stores secrets (and its limitations) motivates the external secrets approach in assignment-2.
