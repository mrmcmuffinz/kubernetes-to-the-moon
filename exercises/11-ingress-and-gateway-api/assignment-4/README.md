# Assignment 4: Advanced Gateway API Routing with NGINX Gateway Fabric

This is the fourth of five Ingress and Gateway API assignments. Assignment 3 covered Gateway API fundamentals using Envoy Gateway. This assignment covers advanced HTTPRoute patterns (header matching, query-param matching, traffic splitting, filters) using NGINX Gateway Fabric v2.5.1 as a second implementation. Running both Envoy Gateway and NGINX Gateway Fabric in the same cluster proves the same Gateway API YAML works across implementations, just as assignments 1 and 2 proved for Ingress.

## Files

| File | Purpose |
|---|---|
| `prompt.md` | The generation prompt |
| `README.md` | This overview |
| `ingress-and-gateway-api-tutorial.md` | Step-by-step tutorial teaching advanced HTTPRoute patterns with NGINX Gateway Fabric |
| `ingress-and-gateway-api-homework.md` | 15 progressive exercises across five difficulty levels |
| `ingress-and-gateway-api-homework-answers.md` | Complete solutions with diagnostic reasoning and common mistakes |

## Recommended Workflow

Work through the tutorial first. It installs NGINX Gateway Fabric v2.5.1 via Helm, confirms its `nginx` GatewayClass is ready, and then walks through header matching, query-param matching, method matching, combined matches, traffic splitting, `RequestHeaderModifier`, `RequestRedirect`, `URLRewrite`, and `ResponseHeaderModifier`. The tutorial includes a side-by-side example of the same HTTPRoute YAML applied under both Envoy Gateway and NGINX Gateway Fabric to reinforce the implementation-agnostic lesson. The homework then drills each piece.

## Difficulty Progression

Level 1 is NGINX Gateway Fabric basics: install, create a Gateway, attach an HTTPRoute, verify with headers. Level 2 is advanced matching: header match, query-param match, method match. Level 3 is debugging: filter applied in the wrong order, header match case-sensitivity mistake, traffic split with misreported weights. Level 4 is filters: RequestHeaderModifier add/set/remove, RequestRedirect with status and scheme, URLRewrite prefix replacement. Level 5 is comprehensive: a canary deployment with traffic shift, a compound debug, and a production-style pattern with four filters chained.

## Prerequisites

Complete `exercises/11-ingress-and-gateway-api/assignment-3` first. This assignment reuses Gateway API CRDs and vocabulary. Envoy Gateway from assignment 3 can stay installed; the tutorial runs NGINX Gateway Fabric alongside it.

## Cluster Requirements

A multi-node kind cluster with extraPortMappings for 80 and 443. See `docs/cluster-setup.md#multi-node-kind-cluster`. Gateway API CRDs v1.5.1 are required (`docs/cluster-setup.md#gateway-api-crds`); the tutorial installs NGINX Gateway Fabric v2.5.1 via its Helm chart.

## Estimated Time Commitment

The tutorial takes 60 to 90 minutes. The 15 exercises together take four to six hours. Level 1 runs 15 to 20 minutes per exercise; Level 2 runs 20 to 30 minutes; Level 3 debugging runs 25 to 35 minutes per exercise because diagnosing filter-order bugs requires reading raw HTTP responses; Level 4 runs 25 to 35 minutes; Level 5 runs 35 to 50 minutes per exercise.

## Scope Boundary and What Comes Next

This assignment covers advanced Gateway API HTTPRoute features. Migration from Ingress to Gateway API is assignment 5. Experimental Gateway API routes (TCPRoute, TLSRoute, UDPRoute, GRPCRoute) are out of 2026 CKA scope. NGINX-specific extensions via `NginxProxy` CRD are out of scope; this assignment focuses on upstream Gateway API conformance.

## Key Takeaways After Completing This Assignment

After finishing all 15 exercises you should be able to install NGINX Gateway Fabric v2.5.1 alongside Envoy Gateway and confirm both GatewayClasses are Accepted, construct HTTPRoute `matches` with path + header + query + method conditions and reason about which rule wins when multiple could match, configure header-based routing (canary by `X-Tenant`, for example), split traffic between backends with `backendRefs[].weight`, apply the four main filter types (`RequestHeaderModifier`, `RequestRedirect`, `URLRewrite`, `ResponseHeaderModifier`), use `URLRewrite` with both `ReplacePrefixMatch` and `ReplaceFullPath`, read an HTTP response and diagnose which filter produced each transformation, distinguish case-sensitive vs case-insensitive matching for header names vs values, observe that the same HTTPRoute YAML (with only parentRefs changed) produces identical behavior under Envoy Gateway and NGINX Gateway Fabric, and produce a canary-deployment pattern with weighted backendRefs.
