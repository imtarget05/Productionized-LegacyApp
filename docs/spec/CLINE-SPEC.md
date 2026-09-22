# PROJECT SPEC — 02-Productionized-LegacyApp

## 1. Goal

Biến một legacy application thành application có thể vận hành production một cách có kiểm soát.

Project này dùng để chứng minh:

- CI/CD
- containerization
- production hardening
- deployment
- rollback
- health checks
- monitoring
- secrets/config
- backup/restore awareness
- release safety

Không ép thêm AI. AI không phải trọng tâm repo này.

---

# 2. Interview Story

> Tôi nhận một ứng dụng legacy chưa production-ready, chuẩn hóa cấu hình, container hóa, bổ sung test/quality gates, health checks, observability, CI/CD, deployment strategy và rollback để vận hành an toàn hơn.

---

# 3. Core Deliverables

Must have:

- current-state architecture;
- dependency audit;
- Dockerfile;
- local Docker Compose if useful;
- environment-based configuration;
- health endpoint;
- readiness endpoint;
- CI pipeline;
- test stage;
- build artifact;
- deployment stage;
- rollback procedure;
- log strategy;
- monitoring baseline;
- backup/restore documentation;
- incident runbook.

---

# 4. Required Phases

## Phase 0 — Audit

Document:

- current app runtime;
- dependencies;
- database;
- deployment method;
- secrets;
- logging;
- tests;
- known risks.

## Phase 1 — Reproducible Build

- lock dependencies;
- deterministic build;
- `.env.example`;
- clear setup.

## Phase 2 — Containerization

- multi-stage Docker build;
- non-root runtime where possible;
- health check;
- minimal image;
- `.dockerignore`.

## Phase 3 — Application Hardening

- config validation;
- graceful shutdown;
- error handling;
- structured logs;
- health/readiness.

## Phase 4 — CI

Pipeline order:

```text
checkout
-> install
-> lint
-> unit tests
-> build
-> security/dependency checks
-> container build
```

Quality gate chỉ ghi `ENFORCED` nếu chạy thật.

## Phase 5 — CD

At least one real deployment workflow.

Must document:

- environment;
- image tag strategy;
- migration strategy;
- rollback.

## Phase 6 — Observability

At minimum:

- application logs;
- health;
- uptime/status;
- error tracking or metrics.

## Phase 7 — Backup / Restore

Document and test:

- what needs backup;
- retention assumption;
- restore procedure;
- restore verification.

---

# 5. Reliability Scenarios

Prepare demos:

1. bad configuration prevents unsafe startup;
2. unhealthy app fails health check;
3. deployment of bad release can rollback;
4. database migration plan documented;
5. dependency failure visible through logs.

---

# 6. Security

- no secrets in repo;
- least privilege;
- non-root container when practical;
- dependency scan;
- security headers where relevant;
- production error responses hide internals.

---

# 7. Repository Documentation

```text
docs/
  current-state.md
  target-architecture.md
  deployment.md
  rollback.md
  backup-restore.md
  incident-runbook.md
  decisions/
```

---

# 8. Out of Scope

Do not:

- rewrite app into microservices;
- add Kubernetes just for portfolio;
- add AI chatbot;
- claim zero-downtime without proving it;
- claim Sonar Quality Gate enforced when token/server not configured.

---

# 9. Definition of Done

- local build reproducible;
- container runs;
- health/readiness work;
- CI executes real checks;
- deployment is documented/reproducible;
- rollback is tested or clearly reproducible;
- backup/restore has a verified path;
- README contains before/after architecture;
- all claims match evidence.
