# Productionized Legacy App — Legacy Inventory Worker

Câu chuyện dự án: nhận một "legacy" Node.js worker nhỏ và **productionize** nó —
không viết lại business logic, mà chuẩn hóa cách nó chạy: container an toàn, pipeline
quét lỗ hổng, và hạ tầng khai báo bằng Terraform.

## Cấu trúc thư mục (layered)

```
src/
├── server.js              Entry point: listen + graceful shutdown (SIGTERM → drain)
├── app.js                 Composition root: wiring middleware + routes (không business logic)
├── routes/                HTTP layer: health.js, sync.js (chỉ mapping request/response)
├── services/              Business layer: inventoryService.js (logic sync tồn kho)
├── middleware/            Cross-cutting: structured JSON logging, 404, error handler
└── test/                  Smoke tests (node:test) — require app.js, không mở port thật
Dockerfile                 Multi-stage, non-root, HEALTHCHECK
infrastructure/terraform/  Web App for Containers + ACR pull credentials
```

Luồng phụ thuộc: `routes → services` và `middleware → (routes)`; entry point (`server.js`)
là nơi duy nhất mở socket. Business logic không nằm trong route handler.

## Chuẩn hóa đã áp dụng

| Hạng mục | Best Practice | Ở đâu |
|---|---|---|
| Container | Multi-stage build, non-root (`USER node`), HEALTHCHECK | `Dockerfile` |
| Dependencies | `npm ci --omit=dev` + lock file; loại bỏ `pg`/`redis` không dùng (thu nhỏ attack surface) | `src/package.json` |
| Runtime | Graceful shutdown (SIGTERM → drain), JSON structured logs, JSON 404/error | `src/server.js`, `src/middleware/` |
| Kiến trúc | Layered folders: entry point → composition root → routes → services | `src/` |
| Tests | Smoke tests với `node:test` (không thêm dependency) | `src/test/` |
| CI | npm test → Trivy scan (fs + image) → build | `.github/workflows/ci.yml` |
| CD | Push ACR + restart Web App (image pull) | `.github/workflows/ci.yml` (job `deploy`) |
| IaC | Web App for Containers + health probe + log retention | `infrastructure/terraform/` |

## Chạy local

```bash
cd src && npm ci --omit=dev
npm start                 # http://localhost:3000/health
npm test                  # 3 smoke tests
```

## Chạy container

```bash
docker build -t legacy-inventory-worker .
docker run -p 3000:3000 legacy-inventory-worker
curl localhost:3000/health
```

## Deploy lên Azure

1. `cd infrastructure/terraform && terraform init && terraform apply`
   (tạo Resource Group + Service Plan + Web App; ACR dùng chung `sharedacr`).
2. Cấu hình GitHub secrets: `ACR_LOGIN_SERVER`, `ACR_USERNAME`, `ACR_PASSWORD`,
   `AZURE_CREDENTIALS`.
3. Push code → CI test + scan + push image → restart Web App để pull image mới.

## Lưu ý
- Backend `azurerm` cho Terraform state đang được comment — bật sau khi tạo Storage
  Account backend.
- ACR `sharedacr` cần `admin_enabled = true` (dùng `admin_username/password`).
