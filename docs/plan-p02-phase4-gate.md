# P02 — Phase 4 Gate: Productionized LegacyApp Audit & Acceptance

> Scope: `Productionized-LegacyApp` (repo root = app root, không có prefix `02-Productionized-LegacyApp/`).
> Audit date: 2026-09-20. Nguồn verify trực tiếp: `src/`, `Dockerfile`, `src/server.js`,
> `src/middleware/http.js`, `src/test/smoke.test.js`, `.github/workflows/ci.yml`,
> `infrastructure/terraform/main.tf`.

---

## 1. Hiện trạng (verified — có file:line)

| Hạng mục | Trạng thái | Evidence |
|---|---|---|
| `POST /sync` stub no-op | ❌ Chưa usable | `src/services/inventoryService.js:7-9` — `function syncInventory()` không nhận tham số, `return { message: 'Inventory synced successfully' }`. `src/routes/sync.js:9-11` gọi `syncInventory(req.body)` nhưng arg bị bỏ qua hoàn toàn. Không validation, không dùng body, không phân biệt item/qty. |
| Smoke tests | ⚠️ Có nhưng mỏng (3 tests) | `src/test/smoke.test.js:13-57` — 3 cases: `GET /health` 200 + `status=healthy`, `POST /sync` 200 + message, unknown route 404 JSON. Không test body validation, không test error path, không test graceful shutdown, không test correlation-id. |
| Dockerfile non-root + HEALTHCHECK | ✅ Có rồi | `Dockerfile:11` `USER node`; `Dockerfile:12-13` `COPY --chown=node:node`; `Dockerfile:16-17` `HEALTHCHECK ... /health`. Multi-stage (`node:18-alpine` builder + runtime), `.dockerignore` loại `test/`. |
| `server.js` SIGTERM drain | ✅ Có rồi | `src/server.js:14-22` — `shutdown()` gọi `server.close(() => process.exit(0))`, hard-stop `setTimeout 10s`, listen `SIGTERM` + `SIGINT`. Chưa verify thực tế bằng `docker stop` timing. |
| Logging JSON structured | ✅ Có rồi | `src/middleware/http.js:6-21` `requestLogger` log 1 dòng JSON (`level,time,msg,method,path,status,durationMs`); `src/server.js:11,15` log JSON `listening/received`. Parse được bởi Azure Log Analytics. |
| Correlation-id | ❌ Thiếu | `src/middleware/http.js` không sinh/propagate `x-correlation-id` hay `x-request-id`. Log không có trường trace → không trace xuyên suốt request → Phase 8 observability bị chặn. |
| `GET /health` | ✅ Có | `src/routes/health.js:8-10` trả `{ status:'healthy', version:'1.0.0' }`. Được Dockerfile HEALTHCHECK + App Service `health_check_path = "/health"` (`main.tf:51`) dùng. |

---

## 2. Bug phải fix (block Phase 4 DONE)

### B1. `ci.yml` paths sai — CI không bao giờ trigger đúng
- File: `.github/workflows/ci.yml:6,8` — `paths: ['02-Productionized-LegacyApp/**']`.
- Thực tế: repo root **chính là** app root (`src/`, `Dockerfile`, `infrastructure/` nằm ngay root, không có thư mục `02-Productionized-LegacyApp/`).
- Hệ quả: push/PR vào `main` không match path → job `test-and-scan` skip; `working-directory: 02-Productionized-LegacyApp/src` (line 25) + `context: 02-Productionized-LegacyApp` (lines 44, 78) đều trỏ thư mục không tồn tại → build fail khi CI có chạy.
- Fix: sửa paths → `['src/**','Dockerfile','.dockerignore','.github/workflows/ci.yml','infrastructure/**']` (hoặc bỏ `paths` hẳn); `working-directory: src`; `context: .`.

### B2. Trivy `exit-code: 0` — scan không gate
- File: `.github/workflows/ci.yml:36`, `ci.yml:55` — cả 2 step Trivy (fs + image) đều `exit-code: '0'`.
- Hệ quả: có CVE CRITICAL/HIGH vẫn pass → DevSecOps vô nghĩa, Phase 5 gate fail.
- Fix: `exit-code: '1'` + `severity: 'CRITICAL,HIGH'` (+ `ignore-unfixed: true` nếu muốn giảm noise). Thêm `exit-code` gate riêng cho image scan.

### B3. Base `node:18` EOL vs CI `node:20` — drift runtime
- File: `Dockerfile:2,8` `FROM node:18-alpine` vs `ci.yml:21` `node-version: '20'`.
- Node 18 đã EOL (04/2025); test trên 20 nhưng ship 18 → rủi ro runtime khác biệt, Trivy báo EOL base.
- Fix: đồng bộ lên `node:20-alpine` (hoặc `node:22-alpine` LTS hiện tại) ở cả 2 stage + pin digest (`FROM node:20-alpine@sha256:...`).

### B4. Backend `azurerm` commented — state local
- File: `infrastructure/terraform/main.tf:9-15` — `backend "azurerm" { ... }` bị comment toàn bộ.
- Hệ quả: `terraform apply` dùng local state → team overwrite nhau, không audit, không lock → không production-ready.
- Fix: tạo `tfstate-rg` + Storage Account + container trước, uncomment backend với `key = "inventory-sync.terraform.tfstate"`, chạy `terraform init -migrate-state`.

### B5. ACR admin auth anti-pattern
- File: `infrastructure/terraform/main.tf:27-31` comment `yêu cầu admin_enabled = true`; `main.tf:54-55` dùng `admin_username/admin_password` cho Web App pull image.
- Hệ quả: credential dài hạn, scope toàn registry, leak qua `app_settings`/state → vi phạm "No secrets in repo" (AGENTS.md §3), ACR admin là legacy anti-pattern.
- Fix: tắt admin (`admin_enabled = false`), dùng Managed Identity + `AcrPull` role assignment cho Web App / AKS kubelet identity; tham chiếu image bằng digest thay vì `:latest` (xem Phase 6).

---

## 3. Acceptance Phase 4 (phải có evidence thật, không fabricate)

Gate = TẤT CẢ checklist dưới pass với log/command output dán vào PR hoặc `docs/evidence/phase4/`:

- [ ] **A1. `docker build` pass**: `docker build -t legacy-inventory-worker:phase4 .` từ repo root thành công, không warning EOL base (sau fix B3).
- [ ] **A2. `docker run` + `GET /health` 200**: `docker run -d -p 3000:3000 --name legacy-p4 <img>` → `curl -s localhost:3000/health` trả `{"status":"healthy",...}` status 200. Dán output.
- [ ] **A3. `POST /sync` usable**: sau khi fix stub (nhận `req.body`, validate `item/qty`, trả echo + validation 400), `curl -X POST localhost:3000/sync -H 'Content-Type: application/json' -d '{"item":"x","qty":1}'` trả 200 có payload; body rỗng/sai trả 400 JSON. Dán cả 2 outputs.
- [ ] **A4. SIGTERM graceful**: `time docker stop -t 30 legacy-p4` exit 0, log chứa `received SIGTERM, draining`, stop time < 10s (khớp `server.js:18` hard-stop). Dán log + timing.
- [ ] **A5. Non-root verified**: `docker exec legacy-p4 whoami` → `node`; `docker inspect` không có `User: root`. Dán output.
- [ ] **A6. Resource limits**: run với `--memory=256m --cpus=1.0` (hoặc compose `deploy.resources.limits`) app vẫn `GET /health` 200; `docker stats --no-stream` dán snapshot. Document limits đề xuất cho App Service B1 / AKS requests/limits.
- [ ] **A7. Evidence thật**: mọi metric là output thật (AGENTS.md §2 evidence-first). Không ước lượng latency/RPS ở Phase 4 — để dành Phase 8 đo bằng k6/App Insights.

Lệnh mẫu gom evidence một lượt:

```bash
docker build -t legacy-inventory-worker:phase4 .
docker run -d -p 3000:3000 --memory=256m --cpus=1.0 --name legacy-p4 legacy-inventory-worker:phase4
curl -s -w '\n%{http_code}\n' localhost:3000/health
curl -s -w '\n%{http_code}\n' -X POST localhost:3000/sync -H 'Content-Type: application/json' -d '{"item":"widget","qty":2}'
docker exec legacy-p4 whoami
docker stats --no-stream legacy-p4
time docker stop -t 30 legacy-p4
docker logs legacy-p4 2>&1 | tail -20
```

---

## 4. Phase 5–11 outline

| Phase | Mục tiêu | Việc chính | Gate |
|---|---|---|---|
| 5. DevSecOps | Scan thành gate thật | Fix B1+B2; thêm SonarCloud (quality gate, coverage), Trivy `CRITICAL,HIGH → fail`; branch protection require `test-and-scan` pass | PR demo: push CVE fixture → CI đỏ; fix → CI xanh |
| 6. Artifact (ACR + SHA) | Immutable release | Fix B5 (Managed Identity + `AcrPull`); tag `:<sha>-<run>` + `:latest` float; Web App/AKS pin digest; giữ `health_check_path /health` | `az acr repository show-tags` + `docker inspect` digest khớp manifest deploy |
| 7. AKS namespace `legacyapp` | Runtime K8s chuẩn | Deployment (2 replicas, `readinessProbe/livenessProbe /health`, `resources.requests/limits`), Service ClusterIP, Namespace `legacyapp` (song song `flashsale` của P01, GitOps truth ở P03 ArgoCD), `kubectl kustomize` render clean | `kubectl -n legacyapp get pods` Running + `kubectl kustomize` pass |
| 8. Observability | Thấy được traffic | Thêm correlation-id middleware (fix gap §1); App Insights/OpenTelemetry (RPS, p50/p95 latency, error rate); dashboard + alert 5xx/latency | Dashboard screenshot + alert test fire |
| 9. Reliability | Deploy không downtime | Rolling update (`maxSurge 1/maxUnavailable 0`), PodDisruptionBudget, readiness gate; runbook rollback (`kubectl rollout undo`) + drill | `kubectl rollout history` + drill log zero-failed-requests (k6 smoke) |
| 10. DR stateless | Mất pod/node không mất data | Xác nhận stateless (không volume local, state ở DB ngoài); multi-replica + anti-affinity; backup IaC/state backend (fix B4); RTO/RPO doc | Kill pod/node drill + recover time log |
| 11. HPA | Co giãn theo tải | HPA `cpu 70% / custom RPS`, `minReplicas 2 maxReplicas 6`; P02 **HPA-only, out-of-scope KEDA** (KEDA dành cho P01 worker event-driven); k6 load test chứng minh scale-out/in; doc cost note (B1 vs AKS node pool) | `kubectl get hpa` + k6 graph scale events |

---

## 5. Next action (Phase 4 close-out)

1. Fix B1–B3 trước (unblock CI + build reproducible).
2. Implement `POST /sync` usable + validation + test bổ sung (nâng từ 3 lên ≥5 tests).
3. Thêm correlation-id (1 middleware, chuẩn bị Phase 8).
4. Chạy bộ lệnh A1–A7, lưu output vào `docs/evidence/phase4/`, tick checklist.
5. B4 + B5 có thể song song (IaC track) nhưng phải xong trước khi claim Phase 6/7.
---
## Approved
- Status: APPROVED by user 2026-09-21
- Scope locked: P01 BUILD NEW, P02 MODERNIZE OLD, P03 OPERATE BOTH. Phase 4 P02 gate → Phase 5 DevSecOps → Phase 11 KEDA vs HPA.
- Owner: build orchestrator. Cline agents: read-only trừ khi được giao task, không sửa 2 file này.
