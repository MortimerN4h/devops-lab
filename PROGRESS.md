# DevOps Lab – Progress & Context (AGENT: ĐỌC FILE NÀY ĐẦU TIÊN)

> Cập nhật file này sau MỖI bước hoàn thành. Session mới: đọc file này, rồi tiếp tục từ mục 7 "Trạng thái hiện tại".

## 1. Bối cảnh & cách làm việc
- User là người mới với nhiều ngôn ngữ; mục tiêu là **HỌC**, không phải nhận code làm sẵn. Trả lời bằng **tiếng Việt**.
- **User tự chạy lệnh** (build/run/test/git...), agent hướng dẫn + giải thích. Agent chỉ được viết/sửa file source.
- Nhịp độ: mỗi lượt làm NHIỀU việc hơn (gộp nhiều bước liên quan) nhưng VẪN giải thích đầy đủ mọi lệnh/dòng MỚI; lệnh đã giải thích rồi thì nhắc ngắn. Không đưa lệnh nào mà không giải thích.
- **Mỗi app BẮT BUỘC có `README.md` theo khuôn của `apps/nodejs` và `apps/python`** (user nhắc 2026-11-19, kiến thức web còn yếu): chạy nhanh → đường đi request → **file nào cần quan tâm để build/run (chung cho MỌI dự án ngôn ngữ đó)** tách khỏi file code → Dockerfile từng dòng → compose từng dòng → còn thiếu so với production. Viết NGAY khi tạo app, không đợi user hỏi. Vd Java: pom.xml là gì, sinh ra thế nào.
- Trọng tâm học: **cách build/run của từng ngôn ngữ**, route frontend→backend, REST API (GET/POST/PUT/DELETE), mã lỗi + JSON lỗi, test API, Docker/compose/Nginx/ECR/Terraform/DNS/HTTPS/CI-CD. Source code KHÔNG phải trọng tâm → agent viết to, đầy đủ, đẹp.
- **Giao diện** (user yêu cầu 2026-11-18): phải lớn, chỉnh chu như web production (navbar, hero, thống kê, tìm kiếm/lọc, toast, skeleton, empty state, footer, responsive), KHÔNG làm UI sơ sài. Mẫu tham khảo: frontend React của `apps/nodejs`.
- Build image trên **GitHub Actions** (không build trên EC2); bastion để viết code, test nhanh, pull ECR, chạy compose.
- Repo GitHub **public**: `git@github.com:MortimerN4h/devops-lab.git` (Actions free không giới hạn cho public; vẫn dùng `paths` filter). Repo private cũ bị khóa Actions do billing → bỏ.
- **Riêng tư (repo public)**: KHÔNG ghi tên công ty, tên leader, nơi làm việc, email cá nhân vào bất kỳ file nào được commit. `DAILY_REPORT.md` chỉ lưu local (đã gitignore). Commit dùng email noreply của GitHub.

## 2. Yêu cầu bài tập (tuần này)
1. Source code đơn giản: php, nodejs, python, golang, java (spring + quarkus), ruby on rails → mỗi cái có Dockerfile; docker-compose chạy tất cả; push lên **AWS ECR**.
2. **Terraform** tạo EC2, tự pull image từ ECR và deploy.
3. **Nginx** làm reverse proxy.
4. DB: mysql, postgres, mongodb, redis, dynamodb; dump data; mỗi app hiển thị data ra web.
5. Subdomain `node.abcxyz.com`, `golang.abcxyz.com`, `quarkus.abcxyz.com`... qua Route53 hosted zone → trỏ về EC2.
6. HTTPS (certbot / Let's Encrypt).
7. Tự động deploy bằng **GitHub Actions** (CI/CD).
Mục đích học: network, DNS, cert, Dockerfile, compose, DB admin.

## 3. Quy ước
- **Commit**: tiếng Anh, thì mệnh lệnh (Add/Fix/Update), ≤ ~50 ký tự, không dấu chấm cuối. User tự `git commit`/`push`.
- **Thư mục**: mỗi tuần một thư mục `task_week1/`, `task_week2/`... (week1: `apps/`, `terraform/`, `tests/`, `API.md`). `.github/workflows/` BẮT BUỘC ở gốc repo; workflow dùng `paths: task_weekN/**` + `working-directory`. `scripts/` ở gốc chứa script tiện ích.
- **Daily report**: khi user nhờ, đọc `DAILY_REPORT.md` (file LOCAL, gitignore, không có trên GitHub; cách điền ghi ở đầu file đó) + roadmap/nhật ký ở đây. Nếu máy không có file đó thì hỏi user.
- **Cổng**: tránh cổng thông dụng (8080...) khi forward qua IDE vì có thể trùng với dịch vụ trên laptop. Node 18080, Python 18081, Go 18082, Java 18083, .NET 18084.

## 4. Thiết kế app (CHỐT)
- Kiến trúc 3 container/app: **frontend** (build tĩnh + nginx, proxy `/api` → backend) → **backend** (API) → **DB**. Chỉ frontend publish port ra ngoài.
- Chỉ **2 frontend**: React (Vite) và Angular, dùng lại cho các backend. Backend + DB khác nhau hoàn toàn (5 app, CHỐT):
  Node/Express + MongoDB (React) · Python/FastAPI + PostgreSQL (Angular) · Go/Gin + PostgreSQL + Redis cache (React) · Java/Spring Boot + MySQL (Angular) · .NET/ASP.NET Core + DynamoDB (React).
- Hợp đồng API duy nhất cho mọi backend: `task_week1/API.md`. Test API dùng chung: `task_week1/tests/api-test.sh` (`BASE_URL=http://localhost:<port>`; mặc định 18080; 18 check).
- Note có `dueDate` (hạn chót, tùy chọn): chuỗi `YYYY-MM-DD` hoặc `null`, phải là ngày có thật (2026-02-30 → 400); PUT bỏ trống → về `null`. SQL dùng cột `DATE`, Redis/Mongo/DynamoDB lưu chuỗi. UI hiển thị ngày dạng `dd/mm/yyyy` bằng component tự viết `DateInput.jsx` (input date gốc theo locale trình duyệt, không ép được); không hiển thị `createdAt` (chỉ để sắp xếp). Footer không ghi stack.
- Mỗi app: `apps/<tên>/{backend,frontend,db,docker-compose.yml}` (compose riêng để chạy thử ở local). Production gộp tất cả trong `task_week1/deploy/` (1 edge Nginx theo subdomain).
- DB seed bằng script mount vào `/docker-entrypoint-initdb.d/` (chỉ chạy lần đầu khi volume trống).

## 5. Máy làm việc (bastion)
- EC2 Ubuntu 24.04 (t3.small, ~2GB RAM + swap 2GB), tạo bằng Terraform: `task_week1/terraform/bastion/` (`main.tf`, `variables.tf`, `outputs.tf`; điền `terraform.tfvars` từ file `.example`, file này và `terraform.tfstate` đã gitignore). Region `us-east-1`. SSH từ Antigravity bằng key `~/.ssh/devops-bastion` (trên PC).
- Danh tính AWS: IAM **role** `devops-bastion-role` (instance profile, hiện là AdministratorAccess cho account học tập → thu hẹp sau khi làm Terraform deploy). KHÔNG có access key trên máy. Kiểm tra: `aws sts get-caller-identity` phải ra `assumed-role/devops-bastion-role/...`.
- Dựng lại máy khác nhanh: `bash scripts/bootstrap-bastion.sh` (swap + Docker + Terraform + AWS CLI; chạy lại an toàn), cần SSH key GitHub của máy đó (thêm vào GitHub → Settings → SSH keys) để clone repo private.
- Lưu ý IP public của bastion đổi sau stop/start (không có Elastic IP) → cập nhật `HostName` trong `~/.ssh/config` trên PC; IP của PC đổi thì sửa `my_ip_cidr` rồi `terraform apply` (hoặc sửa security group trên Console).

## 6. Roadmap (XONG phạm vi tuần 1 – 2026-11-25)
**Phạm vi (user chốt 2026-11-23): 5 app.** Bỏ Quarkus, Rails; PHP chỉ là dự phòng cho .NET → không làm.
- [x] Bước 0: Bastion (swap, git, docker, compose, aws cli, terraform) bằng Terraform + IAM role
- [x] Bước 1: Docker cơ bản (image/container/layer/port/volume/network)
- [x] Bước 2: Node Express + MongoDB + React – `https://node.<domain>`
- [x] Bước 3: Python FastAPI + PostgreSQL + Angular – `https://python.<domain>` (2026-11-23)
- [x] Bước 4: Go Gin + PostgreSQL + Redis cache + React – `https://go.<domain>` (2026-11-25)
- [x] Bước 6: Java Spring Boot + MySQL + Angular – `https://java.<domain>` (2026-11-25)
- [x] Bước 7': .NET ASP.NET Core + DynamoDB + React – `https://dotnet.<domain>` (2026-11-25)
- [x] Bước 9: Gộp mọi app + Nginx theo subdomain → thay bằng `task_week1/deploy/` chạy trên app server
- [x] Bước 11: ECR, OIDC + IAM role cho GitHub Actions
- [x] Bước 12: Terraform EC2 app + user_data
- [x] Bước 13: Route53 subdomain · [x] Bước 14: HTTPS certbot · [x] Bước 15: CI/CD test → push ECR → deploy (SSM)
- ~~Bước 5 PHP, Bước 7 Quarkus, Bước 8 Rails~~ (bỏ theo phạm vi mới)
- [ ] (Tùy chọn) Bước 12b: Ansible cấu hình EC2 – chưa làm, không bắt buộc
- [ ] Việc tồn (không gấp): xem mục 7 "Còn tồn".

## 7. Trạng thái hiện tại
**5 app chạy HTTPS trên 1 EC2 `devops-app` (m7i-flex.large, 8 GB), mỗi app có workflow riêng (test → push → deploy → smoke test `vars.<APP>_URL`).**

| App | Local | Backend + DB | Workflow | Ghi chú prod |
|---|---|---|---|---|
| node | 18080 | Express + MongoDB 7 | `node.yml` | volume `node-mongo-data`; backend chạy `USER node` |
| python | 18081 | FastAPI + PostgreSQL 16 | `python.yml` | `PYTHON_DB_PASSWORD` trong `.env` server |
| go | 18082 | Gin + PostgreSQL 16 + Redis 7 (cache) | `go.yml` | `GO_DB_PASSWORD`; Redis không volume |
| java | 18083 | Spring Boot 3.5 + MySQL 8.4 | `java.yml` | `JAVA_DB_PASSWORD`, `JAVA_DB_ROOT_PASSWORD` |
| dotnet | 18084 | ASP.NET Core (.NET 10) + DynamoDB | `dotnet.yml` | bảng THẬT `devops-lab-dotnet-notes` (Terraform), không container DB, không key |

**Cách deploy chung** (chi tiết: `task_week1/deploy/README.md`):
- `deploy/docker-compose.yml` = `edge` nginx (cổng 80/443 duy nhất, template `nginx/http|https/default.conf.template` chọn bằng `NGINX_MODE`) + mỗi app 1 network riêng, backend alias `backend`, `restart: unless-stopped`. `.env` server: REGISTRY, DOMAIN, NGINX_MODE, các mật khẩu DB (không commit).
- `deploy/deploy.sh` (trên server): pull MỌI image `*-frontend|*-backend` → `up -d --remove-orphans` → nếu hash `nginx/` đổi: `compose run --rm --no-deps edge nginx -t` rồi `restart edge` → `image prune`.
- Composite action `.github/actions/deploy-to-server`: tìm instance theo tag → SSM Run Command (`git pull --ff-only` + `deploy.sh`). Dùng bởi job deploy của 5 workflow app + `deploy.yml` (`deploy-config`, chạy khi `deploy/**` đổi, trừ `.md`). Chung `concurrency: deploy-app-server` (job chờ bị huỷ = vô hại vì deploy.sh luôn cập nhật TẤT CẢ).
- **Thứ tự thêm app mới**: ECR → workflow → DNS → cert → compose + edge block → biến `<APP>_URL`. Block 443 trỏ cert chưa có → nginx không start → sập mọi app.
- IAM server `devops-app-role`: ECR read-only, SSM core, inline `dotnet-notes-table` (6 action DynamoDB, chỉ bảng đó). EC2 `metadata_options`: IMDSv2 required, hop limit 2 (container lấy key qua IMDS).

**Chi tiết từng app** (cái gì đặc biệt, để nhớ khi đọc lại):
- **Node**: Express + Mongo, seed `db/seed.js`. React là UI mẫu cho mọi app.
- **Python**: FastAPI (psycopg3 async pool, tự đọc body để trả đúng mã lỗi API.md thay vì 422, Swagger `/api/docs`, user non-root) + PostgreSQL (`db/init.sql`; healthcheck `pg_isready -h 127.0.0.1` vì lúc init Postgres chỉ nghe socket) + Angular 19 (standalone, signals, `NotesStore`; selector `header[app-navbar]` để dùng lại CSS React).
- **Go**: Gin + pgx/v5 pgxpool + go-redis cache-aside (`cache:notes`/`cache:note:<id>`, TTL 60s, ghi PG rồi DEL, Redis lỗi = MISS, header `X-Cache`). Redis cache thuần `--save "" --appendonly no --maxmemory 64mb --maxmemory-policy allkeys-lru`. Image distroless ~18 MB. (23/11 từng dùng Redis làm DB, đổi 25/11 theo yêu cầu user.)
- **Java**: Spring Boot 3.5.0 / Java 21, JPA (`ddl-auto=none`, `open-in-view=false`, graceful shutdown), Jackson `readTree` tự validate, `@RestControllerAdvice` (404 cho route lạ + 405). Biến môi trường `SPRING_DATASOURCE_*` ghi đè `application.properties`. Image `eclipse-temurin:21-jre-alpine`, user 10001, `-XX:MaxRAMPercentage=75`, ~400 MB; RAM MySQL ~450 MB + JVM ~220 MB. Healthcheck MySQL dùng `$$MYSQL_PASSWORD`.
- **.NET**: Minimal API một file `Program.cs` + `AWSSDK.DynamoDBv2`; id UUID v7; Update/Delete có `ConditionExpression attribute_exists(id)`. `DYNAMODB_ENDPOINT` có = DynamoDB Local (local/CI, `amazon/dynamodb-local -inMemory` + one-shot `dynamodb-init` chạy `db/init.sh`), không có = AWS thật qua credential chain. Bảng thật seed 1 lần từ bastion: `TABLE_NAME=$(terraform -chdir=task_week1/terraform/app output -raw dotnet_table) AWS_REGION=us-east-1 sh task_week1/apps/dotnet/db/init.sh`. Image ~180 MB, RAM ~60 MB.

**Còn tồn** (không gấp):
- `user_data` chưa ghi `*_DB_PASSWORD` → dựng lại server phải thêm tay vào `.env` (hoặc chuyển sang SSM Parameter Store).
- `package-lock.json` + `npm ci` cho các frontend/Node backend; `mem_limit` cho container; deploy theo tag commit thay vì `latest`; backup DB; `git sparse-checkout` trên server.
- Chi phí: EC2 m7i-flex.large + Elastic IP + zone $0.5/tháng + DynamoDB (~0). Destroy `terraform/app` khi không dùng (mất data Mongo/PG/MySQL + cert; Let's Encrypt giới hạn 5 cert trùng tên/tuần); KHÔNG destroy `terraform/dns`.

**Bài học / sự cố đã gặp** (giữ lại để nhớ):
- `terraform plan` đòi replace server vì AMI SSM "current" đổi → `lifecycle { ignore_changes = [ami] }`. Đổi `instance_type` = stop/start tại chỗ, giữ đĩa + Elastic IP.
- 502 sau deploy (25/11): nginx resolve tên upstream MỘT lần lúc start, container bị tạo lại có IP mới → edge giữ IP cũ. Sửa: `resolver 127.0.0.11 valid=10s ipv6=off;` + `set $upstream ...; proxy_pass $upstream;` ở edge và mọi frontend nginx.conf.
- `depends_on` chỉ chờ container start, không chờ sẵn sàng → dùng healthcheck `service_healthy`, hoặc vòng chờ trong script (dynamodb-init).
- CI OIDC `Not authorized to perform sts:AssumeRoleWithWebIdentity` (19/11): GitHub gửi `sub` dạng mới có ID số → trust policy chấp nhận cả 2 dạng (`github_repo_with_ids`). Debug: CloudTrail event `AssumeRoleWithWebIdentity` → `userName`.
- Tài khoản GitHub từng bị khoá billing (repo private) → chuyển sang repo public `devops-lab`.

## 7b. Task tuần 2: RKE2 + Longhorn (bắt đầu 2026-11-25)
**Yêu cầu:** cài RKE2 trên EC2, **1 master + 1 worker**, rồi cài **Longhorn** (storage cho Kubernetes). Thư mục `task_week2/`.
**Cách làm (chốt):** Terraform chỉ tạo máy + security group (`task_week2/terraform/rke2/`); RKE2 và Longhorn **cài tay** từng bước
(user chạy lệnh, agent giải thích) để thấy rõ từng thành phần. Ghi lại trong `task_week2/README.md`.
- Phiên bản (kiểm tra 25/11): RKE2 stable **v1.36.6+rke2r1**; Longhorn **v1.13.0** (cần Kubernetes ≥ 1.34).
- Máy: `devops-rke2-master` + `devops-rke2-worker`, c7i-flex.large (2 vCPU, 4 GB), Ubuntu 24.04, đĩa 30/40 GB gp3,
  hostname `rke2-master`/`rke2-worker` (user_data). SG `devops-rke2-sg`: mọi cổng giữa 2 node (`self`), 22 + 6443 chỉ từ SG bastion.
  Key SSH `~/.ssh/devops-rke2` trên bastion. Quota vCPU tài khoản = 16 (đang dùng 4 + 4 mới).
- Các bước: (1) Terraform 2 node · (2) RKE2 server trên master · (3) RKE2 agent trên worker (token) · (4) kubectl từ bastion
  · (5) chuẩn bị node cho Longhorn (open-iscsi, nfs-common, preflight) · (6) Helm cài Longhorn · (7) thử PVC + pod, xem UI.
- Trạng thái: bước 1 đã viết Terraform, chờ user apply.

## 8. Nhật ký / Kiến thức đã học
- 2026-11-17: swap (fallocate/chmod 600/mkswap/swapon, fstab). Build ở nơi khác rồi push ECR, EC2 chỉ pull+chạy. Terraform = tạo hạ tầng, Ansible = cấu hình trong máy.
- 2026-11-17: Lỗi "permission denied ... docker.sock" = phiên chưa nhận nhóm docker sau usermod (không phải security group) → newgrp/SSH lại.
- 2026-11-17: Docker: client/daemon/image/layer/container, port mapping, volume, network compose (gọi nhau bằng tên service), healthcheck + depends_on, multi-stage build, build context (không COPY file ngoài context), cache layer (COPY package*.json trước).
- 2026-11-17: Git: .gitignore (không commit bí mật/tfstate), SSH key, remote/origin, push -u. API: REST, mã trạng thái 200/201/204/400/404/500, JSON lỗi thống nhất, test bằng curl.
- 2026-11-17: Cổng 8080 từng trùng với nginx trên laptop khi forward qua IDE → đổi 18080.
- 2026-11-18: Terraform cơ bản: block terraform/provider/variable/data/resource/output, init → plan → apply, state. IAM: user + access key (dài hạn) vs role (credential tạm, không lưu key) + instance profile; EC2 thuộc về account chứ không thuộc user. Security group (SSH chỉ từ IP của PC, /32). user_data chạy script lúc boot. Đã chuyển sang bastion mới bằng Terraform.
- 2026-11-18: Lỗi docker.sock trên bastion mới do bootstrap chạy qua user_data bằng root ($USER=root) → đã thêm root vào nhóm docker thay vì ubuntu; sửa script (`id -u`). Git: lịch sử rẽ nhánh (divergent) → `git fetch` + `git reset --hard origin/main` (bỏ commit local), hoặc `git pull --rebase` (giữ cả hai). Thêm `dueDate` vào API + UI.
- 2026-11-18: Actions repo private báo "recent account payments have failed" (startup_failure, 0 job) = khóa billing tài khoản GitHub, không phải lỗi code. Chuyển sang repo public mới `devops-lab` (lịch sử sạch, ẩn thông tin công ty/leader/email; `DAILY_REPORT.md` gitignore). `gh` CLI: auth device flow, `gh variable set`, `gh run list/watch/view --log-failed`, `gh workflow run`.
- 2026-11-19: Route53 hosted zone + NS ở nhà đăng ký ngoài, EC2 app + Elastic IP, certbot webroot + `--deploy-hook`, edge nginx template (`${DOMAIN}`). CI/CD: OIDC (không lưu key), deploy bằng SSM Run Command (không mở 22).
- 2026-11-23: Python + Go lên prod. Edge 1 file cấu hình chung cho mọi app, `deploy.sh` + composite action dùng chung, `concurrency`. Biến repo `<APP>_URL` cho smoke test.
- 2026-11-25: Go đổi sang PostgreSQL + Redis cache-aside. Bài học 502 (resolver Docker). Server nâng m7i-flex.large. Java + MySQL lên prod. .NET + DynamoDB: local dùng DynamoDB Local, prod dùng bảng thật (Terraform + IAM chỉ trên bảng + IMDS hop limit 2). Node backend chạy `USER node`. **Đủ 5 app.**
