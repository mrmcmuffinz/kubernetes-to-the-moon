# Assignment Prompt: Secrets Management — Assignment 1

**Series:** Secrets Management (1 of 2)
**Topic slug:** secrets-management
**Topic directory:** exercises/27-secrets-management/assignment-1/

## Metadata

**Domain:** CKS — Minimize Microservice Vulnerabilities (20%)
**Competencies:** etcd encryption at rest, EncryptionConfiguration, secret exposure patterns
**Prerequisites:** 17-cluster-lifecycle/assignment-3, 01-pods/assignment-2

## Scope — In Scope

*The etcd plaintext problem*
- Demonstrating that base64 in a Kubernetes Secret is encoding, not encryption
- Using etcdctl to read a Secret directly from etcd without decryption: the value appears as base64-encoded plaintext, not ciphertext
- Why this matters: anyone with etcd access (or a backup file) can read all Secrets without Kubernetes RBAC
- etcdctl commands for kind: connecting with the correct cert flags, the ETCDCTL_API=3 environment variable

*EncryptionConfiguration resource*
- The EncryptionConfiguration file structure: resources list (targeting secrets and/or configmaps), providers list per resource
- Provider types: identity (no encryption, plaintext), aescbc (AES-CBC with PKCS7 padding), secretbox (XSalsa20 and Poly1305), kms (external KMS — conceptual only)
- The provider order matters: first provider is used for writes; all providers are tried for reads
- Generating a base64-encoded key for aescbc: head -c 32 /dev/urandom | base64
- The identity provider must be last (or absent) to enforce encryption for all new writes

*Enabling encryption on the API server*
- Writing the EncryptionConfiguration file to a path on the kind control plane node
- Adding --encryption-provider-config flag to the kube-apiserver static pod manifest
- Mounting the EncryptionConfiguration file as a hostPath volume in the static pod manifest
- Verifying the API server restarts cleanly after the change

*Verifying encryption is working*
- Creating a new Secret after enabling encryption
- Using etcdctl to read the new Secret: the value should now be ciphertext (k8s:enc:aescbc:v1:... prefix)
- Using kubectl get secret to confirm Kubernetes still decrypts correctly
- Reading an old Secret (created before encryption was enabled): still plaintext; must be re-encrypted

*Key rotation*
- Adding a new key to the EncryptionConfiguration providers list (new key first, old key second)
- Re-encrypting existing Secrets with: kubectl get secrets --all-namespaces -o json | kubectl replace -f -
- Verifying old Secrets are now encrypted with the new key (etcdctl shows new prefix)
- Removing the old key after all Secrets are re-encrypted

*Secret exposure patterns*
- Environment variable exposure: ENV vars visible via kubectl describe pod, /proc/PID/environ inside the container, and process listings
- Volume mount exposure: Secret as a file in a volume — not in the environment, harder to accidentally log
- Why volume mounts are preferred for sensitive values
- secretKeyRef vs secretRef (mounting all keys) vs volumeMount: trade-offs
- Using projected volumes to combine Secret and ConfigMap mounts
- automountServiceAccountToken: false as a secret exposure reduction (service account token is a Secret)

## Scope — Out of Scope

- External secrets (ESO, Vault): covered in secrets-management/assignment-2
- etcd backup and restore: covered in 17-cluster-lifecycle/assignment-3
- Service account RBAC: covered in 12-rbac

## Environment

Single-node kind cluster with etcdctl installed and access to etcd certificates. The tutorial must document:
1. Installing etcdctl inside the kind control plane container (or running it via a pod)
2. The correct etcdctl connection flags for the kind cluster etcd
3. How to edit the kube-apiserver static pod manifest to enable encryption

## Resource Gate

All Kubernetes resources are in scope.

## Topic-specific Conventions

- Never use real credentials in tutorial examples. Use placeholder values like `supersecretpassword` and `dGVzdC1zZWNyZXQ=` (base64 of "test-secret").
- All etcdctl commands must include the complete cert flags — do not show partial commands.
- Tutorial namespace: `tutorial-secrets-management`.

## Exercise Distribution

- Level 1: Read a Secret from etcd using etcdctl (before encryption), decode the base64 value, confirm it is plaintext
- Level 2: Enable EncryptionConfiguration, create a new Secret, verify it appears as ciphertext in etcd; compare an old Secret (plaintext) with a new one (encrypted)
- Level 3 (debugging): Bare headings. Broken encryption setups (API server fails to start due to wrong key length, identity provider missing causing old Secrets to become unreadable, wrong file mount path)
- Level 4: Full key rotation workflow — enable encryption, re-encrypt all existing Secrets, rotate to a new key, remove the old key, verify
- Level 5 (debugging): A cluster has encryption enabled but a security audit finds some Secrets are still stored as plaintext in etcd; diagnose (Secrets created before encryption was enabled) and remediate
