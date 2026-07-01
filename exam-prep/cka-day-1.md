# CKA Day 1 (Mon, June 22) | Gateway API HTTPRoute

Do the Day 0 primer (`cka-day-0.md`) first. This builds the two skills behind the Sim A Q13
you skipped, attaching an HTTPRoute to a Gateway and the path-plus-header AND-match trap, using
the corpus on your own cluster with answer keys. The exact Sim A scenario itself is left for
your Killer.sh Session 2 on Day 5, where the environment is provided. This is the skill build
that makes that attempt land.

### One-time setup (documented, not part of any exercise)

Install these once on the cluster you will use. Every exercise below provisions its own Gateway
and backends on top and reaches them with `kubectl port-forward`, so no NodePort or `/opt/course`
file is involved.

- [ ] Gateway API CRDs: follow `docs/cluster-setup.md#gateway-api-crds`.
- [ ] NGINX Gateway Fabric: follow "Part 1: Install NGINX Gateway Fabric" in `exercises/11-ingress-and-gateway-api/assignment-4/ingress-and-gateway-api-tutorial.md`. Envoy Gateway is not needed for this slice.

### Exercises

Source: `exercises/11-ingress-and-gateway-api/assignment-4/ingress-and-gateway-api-homework.md`

- [ ] Exercise 1.1
- [ ] Exercise 2.1
- [ ] Exercise 2.2
- [ ] Exercise 2.3

Skip 1.3 in that file; it is the side-by-side comparison that also needs Envoy Gateway. Attempt
each cold against its own Verification and Expected, and open the answer key only after a genuine
attempt. Exercise 2.3 (path, method, and header in a single rule, AND semantics) is the exact
trap from Sim A Q13.

### Optional, only if you also install Envoy Gateway

The plain two-path migration (Q13 task 1) lives in assignment-3, which uses Envoy Gateway. Do it
only if you want that exact shape and do not mind a second controller install (per
`exercises/11-ingress-and-gateway-api/assignment-3/ingress-and-gateway-api-tutorial.md`).

- [ ] `exercises/11-ingress-and-gateway-api/assignment-3/ingress-and-gateway-api-homework.md`: Exercise 2.1

### Check-in

- [ ] Did Exercise 2.3 pass its Verification with AND semantics, so a request that matches only the path, or only the header, does not hit the combined rule? If multiple matches behaved as OR, that is the exact Q13 failure mode, and it is the thing to have solid before the Day 5 session.
