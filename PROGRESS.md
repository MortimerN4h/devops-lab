# DevOps Lab – Progress & Context (AGENT: ĐỌC FILE NÀY ĐẦU TIÊN)

> Cập nhật file này sau MỖI bước hoàn thành. Session mới: đọc file này, rồi tiếp tục từ "Bước hiện tại".

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
- **Cổng**: tránh cổng thông dụng (8080...) khi forward qua IDE vì có thể trùng với dịch vụ trên laptop. Node dùng 18080.

## 4. Thiết kế app (CHỐT)
- Kiến trúc 3 container/app: **frontend** (build tĩnh + nginx, proxy `/api` → backend) → **backend** (API) → **DB**. Chỉ frontend publish port ra ngoài.
- Chỉ **2 frontend**: React (Vite) và Angular (dùng lại cho các backend khác). Backend + DB khác nhau hoàn toàn:
  Node/Express+MongoDB (React, đã xong) · Python/FastAPI+PostgreSQL (Angular) · Go/Gin+Redis (React) · PHP/Laravel+MySQL (Angular) · Spring Boot+MySQL (React) · Quarkus+DynamoDB local (Angular) · Rails API+PostgreSQL (React). (Gán frontend cho Go/PHP/Spring/Quarkus/Rails là đề xuất.)
- Hợp đồng API duy nhất cho mọi backend: `task_week1/API.md`. Test API dùng chung: `task_week1/tests/api-test.sh` (`BASE_URL=http://localhost:<port>`; mặc định 18080; 18 check).
- Note có `dueDate` (hạn chót, tùy chọn): chuỗi `YYYY-MM-DD` hoặc `null`, phải là ngày có thật (2026-02-30 → 400); PUT bỏ trống → về `null`. SQL dùng cột `DATE`, Redis/Mongo/DynamoDB lưu chuỗi. UI hiển thị ngày dạng `dd/mm/yyyy` bằng component tự viết `DateInput.jsx` (input date gốc theo locale trình duyệt, không ép được); không hiển thị `createdAt` (chỉ để sắp xếp). Footer không ghi stack.
- Mỗi app: `apps/<tên>/{backend,frontend,db,docker-compose.yml}` (compose riêng để chạy thử); Bước 9 gộp tất cả + Nginx.
- DB seed bằng script mount vào `/docker-entrypoint-initdb.d/` (chỉ chạy lần đầu khi volume trống).

## 5. Máy làm việc (bastion)
- EC2 Ubuntu 24.04 (t3.small, ~2GB RAM + swap 2GB), tạo bằng Terraform: `task_week1/terraform/bastion/` (`main.tf`, `variables.tf`, `outputs.tf`; điền `terraform.tfvars` từ file `.example`, file này và `terraform.tfstate` đã gitignore). Region `us-east-1`. SSH từ Antigravity bằng key `~/.ssh/devops-bastion` (trên PC).
- Danh tính AWS: IAM **role** `devops-bastion-role` (instance profile, hiện là AdministratorAccess cho account học tập → thu hẹp sau khi làm Terraform deploy). KHÔNG có access key trên máy. Kiểm tra: `aws sts get-caller-identity` phải ra `assumed-role/devops-bastion-role/...`.
- Dựng lại máy khác nhanh: `bash scripts/bootstrap-bastion.sh` (swap + Docker + Terraform + AWS CLI; chạy lại an toàn), cần SSH key GitHub của máy đó (thêm vào GitHub → Settings → SSH keys) để clone repo private.
- Lưu ý IP public của bastion đổi sau stop/start (không có Elastic IP) → cập nhật `HostName` trong `~/.ssh/config` trên PC; IP của PC đổi thì sửa `my_ip_cidr` rồi `terraform apply` (hoặc sửa security group trên Console).

## 6. Roadmap
- [x] Bước 0: Chuẩn bị bastion (swap, git, docker, compose, aws cli, terraform) + tạo bastion bằng Terraform với IAM role
- [x] Bước 1: Docker cơ bản (image/container/layer/port/volume/network)
- [x] Bước 2: Node.js: backend Express+Mongo (CRUD, lỗi JSON), frontend React (UI production), nginx proxy, compose, seed, test API 18/18 (README.md giải thích file/Dockerfile/compose)
- [x] Bước 3: Python FastAPI + PostgreSQL + Angular (requirements.txt) – chạy ở `https://python.<domain>` (2026-11-23)
- [ ] Bước 4 (ĐANG LÀM): Go Gin + Redis (go.mod, multi-stage)
**PHẠM VI MỚI (user chốt 2026-11-23): tổng 5 app, chỉ làm thêm 2: Java Spring Boot + MySQL, và .NET (ASP.NET Core) + DynamoDB Local (dự phòng: PHP nếu bỏ .NET). Bỏ Quarkus, Rails. Trước Java: đổi app server sang m7i-flex.large (hiện t3.small 2GB).**
- [ ] Bước 5: PHP Laravel + MySQL (composer.json) – chỉ làm nếu bỏ .NET
- [ ] Bước 6: Java Spring Boot + MySQL (pom.xml, Maven, multi-stage)
- [ ] ~~Bước 7: Java Quarkus + DynamoDB local~~ (bỏ) → Bước 7': .NET + DynamoDB Local
- [ ] ~~Bước 8: Ruby on Rails API + PostgreSQL~~ (bỏ)
- [ ] Bước 9: docker-compose chạy tất cả + Nginx reverse proxy theo subdomain (cục bộ)
- [x] Bước 11: AWS: ECR, OIDC + IAM role cho GitHub Actions *(làm sớm, ngay sau Node)*
- [x] Bước 15: GitHub Actions: build + push ECR (mỗi app thêm 1 job), rồi deploy tự động lên EC2
- [x] Bước 12: Terraform: EC2 + user_data pull ECR + deploy
- [ ] Bước 12b: Ansible (cấu hình EC2: cài docker, pull ECR, chạy compose)
- [x] Bước 13: Route53 subdomain
- [x] Bước 14: HTTPS certbot
**Thứ tự CHỐT (2026-11-18): làm trọn 1 lát dọc với app Node trước** = Bước 11 → 12 (EC2 app + Nginx) → 13 (Route53 `node.<domain>`) → 14 (HTTPS) → 15 (deploy tự động); sau đó mỗi app mới chỉ thêm image ECR + 1 server block Nginx + 1 bản ghi DNS + cert. Rồi mới tới Bước 3-8.
(Thứ tự có thể điều chỉnh cùng user. Chi phí: destroy tài nguyên AWS sau mỗi buổi thử; stop bastion khi không dùng.)

## 7. Bước hiện tại
- **CI tạm bỏ qua**: tài khoản GitHub bị khóa billing (chờ 1-3 ngày: thêm thẻ / GitHub Student). Trong lúc chờ, build + push image Node lên ECR BẰNG TAY từ bastion (vòng `for c in frontend backend` → `docker build -t <registry>/devops-lab/node-$c:<sha> -t ...:latest` + `docker push --all-tags`). Khi mở khóa: `gh run rerun --failed`.
- Bước 11 xong phần AWS: `terraform/ci/` (ECR `devops-lab/node-*`, OIDC, role `devops-lab-github-actions`), variable `AWS_ROLE_ARN` đã đặt cho repo `devops-lab`.
- **Bước 12-14 XONG (2026-11-19)**: `https://node.<domain>` chạy trên EC2 `devops-app`. Cách làm (để lặp lại cho app khác), domain user mua ở nhà đăng ký ngoài:
  1. `terraform/dns/` = hosted zone (giữ lâu dài, tách riêng để NS không đổi) → copy 4 `name_servers` sang nhà đăng ký → kiểm tra `dig NS <domain> +short`.
  2. Bastion: `ssh-keygen -t ed25519 -f ~/.ssh/devops-app -N ""`. Push `task_week1/deploy/` lên GitHub TRƯỚC (user_data clone repo public).
  3. `terraform/app/` = EC2 `devops-app` (t3.small, SG 80/443 mở, 22 chỉ từ SG bastion, role chỉ ECR read-only, Elastic IP, bản ghi A `node.<domain>`). user_data: swap, Docker, certbot, `amazon-ecr-credential-helper` (pull ECR không cần docker login), clone repo → `/opt/devops-lab/task_week1/deploy`, ghi `.env` (REGISTRY, DOMAIN, NGINX_MODE=http), `docker compose up -d`.
  4. `task_week1/deploy/`: compose production = `edge` nginx (cổng 80/443 duy nhất, template `nginx/http|https/default.conf.template` chọn bằng `NGINX_MODE`) + node-frontend/backend (alias `backend`)/mongo trên network `node`, `restart: unless-stopped`.
  5. HTTPS: trên app server `sudo certbot certonly --webroot -w /var/www/certbot -d node.<domain> ... --deploy-hook "docker exec edge nginx -s reload"` → `NGINX_MODE=https` trong `.env` → `docker compose up -d edge` → `sudo certbot renew --dry-run`.
- **Bước 15 XONG (2026-11-19)**: pipeline test → push → deploy xanh. Deploy tự động bằng **SSM Run Command** (không SSH/không mở 22/không lưu key): `terraform/app` gắn `AmazonSSMManagedInstanceCore` cho `devops-app-role`; `terraform/ci` thêm policy `deploy-ssm` (ec2:DescribeInstances, ssm:SendCommand chỉ document `AWS-RunShellScript` + instance tag `Name=devops-app`, đọc kết quả). Workflow job `deploy` (needs push, `concurrency`): tìm instance theo tag (không có thì skip) → script trên server: `git pull --ff-only` (user ubuntu) → `docker compose pull node-*` → `up -d` → `image prune` → in output; smoke test `vars.NODE_URL/api/health`. Kiểm tra agent: `aws ssm describe-instance-information`.
- **Bước 4 (2026-11-23, đổi 2026-11-25)**: `apps/go/` = Gin + **PostgreSQL (DB chính, `db/init.sql` giống Python) + Redis (cache-aside)** + React chép từ nodejs (chỉ đổi `backend:8080`). User yêu cầu đổi từ "Redis làm DB" sang cache (25/11). Cache: đọc `cache:notes`/`cache:note:<id>` (JSON, TTL 60s) → MISS thì đọc PG rồi SET; ghi PG rồi DEL; Redis lỗi = MISS (app vẫn chạy); header `X-Cache: HIT|MISS`. Redis cache thuần: `--save "" --appendonly no --maxmemory 64mb --maxmemory-policy allkeys-lru`, không volume; backend `depends_on` postgres healthy + redis started. Driver `pgx/v5` + pgxpool. Image distroless (~18 MB). Local 18082, 18/18. Deploy: ECR `go-*`, `go.yml`, DNS, cert, edge block XONG (bản Redis-DB đã chạy prod 23/11); bản PG+cache: compose deploy có `go-postgres` (`GO_DB_PASSWORD` trong `.env` server), `go-redis` không volume, bỏ `go-redis-seed`; `deploy.sh` thêm `up -d --remove-orphans`. Volume cũ `devops-lab_go-redis-data` trên server có thể xóa tay.
- **Bước 3 XONG (2026-11-23)**, deploy 6 bước xanh (cả 3 workflow, smoke test `PYTHON_URL` ok): `apps/python/` = FastAPI (psycopg3 async pool, tự đọc body để trả đúng mã lỗi API.md thay vì 422 của FastAPI, Swagger ở `/api/docs`, chạy user non-root) + PostgreSQL 16 (`db/init.sql` tạo bảng + seed; healthcheck `pg_isready -h 127.0.0.1` vì lúc init Postgres chỉ nghe socket) + Angular 19 (standalone component, signals, `NotesStore` giữ state; selector dạng `header[app-navbar]` để không có thẻ bọc → dùng lại nguyên CSS React). Local: cổng **18081**. Build OK (agent đã build thử). Tiếp: user chạy test 18/18 → ECR repo `python-*` + workflow `python.yml` + deploy (`python.<domain>`, cert). App mới = thêm service + network + server block + bản ghi A + `certbot -d <app>.<domain>`.
  - Deploy Python (2026-11-23, chốt edge **1 file cấu hình chung**): (1) ECR `python-*` XONG; (2) `python.yml` test (BASE_URL 18081) + push ECR (chưa deploy); (3) bản ghi A `python` XONG (thêm `lifecycle { ignore_changes = [ami] }` vì SSM param AMI "current" đổi → plan đòi replace server); (4) certbot `python.<domain>` XONG; (5) compose deploy thêm python-frontend/backend(alias backend)/postgres + network `python` (edge nối cả 2 network) + block `python.${DOMAIN}` trong file edge chung (http + https); mật khẩu `PYTHON_DB_PASSWORD` trong `.env` server (thêm tay; **TODO: user_data chưa ghi biến này** → nếu dựng lại server phải thêm); (6) deploy chung cho mọi app: `deploy/deploy.sh` (trên server: pull MỌI image `*-frontend|*-backend` → `up -d` → nếu hash file `nginx/` khác `.nginx-hash` thì `compose run --rm --no-deps edge nginx -t` rồi `restart edge`; restart chứ không reload vì template chỉ render lúc start) + composite action `.github/actions/deploy-to-server` (tìm instance, SSM: git pull + deploy.sh) dùng bởi node.yml/python.yml (job deploy) và `deploy.yml` (chỉ khi `deploy/**` đổi; app workflow bỏ `deploy/**`). Mọi deploy chung `concurrency: deploy-app-server` (GitHub chỉ giữ 1 job chờ/nhóm, job chờ cũ bị huỷ → vô hại vì deploy.sh luôn cập nhật TẤT CẢ). Repo variable `PYTHON_URL` cho smoke test.
  - Thứ tự đổi vì: block 443 trỏ cert chưa có → nginx không start → sập cả Node. Luôn: DNS → cert → block 443.
- Chi phí app server: t3.small ~$0.02/h + Elastic IP ~$0.005/h + zone $0.5/tháng. Destroy `terraform/app` khi không dùng (mất data Mongo + cert; Let's Encrypt giới hạn 5 cert trùng tên/tuần). KHÔNG destroy `terraform/dns`.
- **Dung lượng app server**: t3.small (2GB) đủ cho Node + vài app nhẹ (Go, Python). Khi thêm app Java (Spring/Quarkus) + DynamoDB local → nâng `instance_type` (account Free plan chỉ cho t3/t4g micro/small, `c7i-flex.large` 4GB, `m7i-flex.large` 8GB → chọn **m7i-flex.large** (8GB, chỉ đắt hơn c7i-flex ~10-15%); t3.medium KHÔNG được phép) trong `terraform.tfvars` rồi `terraform apply` (đổi tại chỗ: stop → đổi loại → start, GIỮ ổ đĩa/data/cert/Elastic IP, downtime ~1-2 phút, KHÔNG cần destroy). Giảm RAM: dùng chung 1 MySQL (PHP + Spring) và 1 PostgreSQL (Python + Rails), mỗi app 1 database; giới hạn JVM (`-XX:MaxRAMPercentage`), Mongo `--wiredTigerCacheSizeGB 0.25`, `mem_limit` trong compose. Theo dõi: `docker stats`, `free -h`.
- **CI OIDC lỗi `Not authorized to perform sts:AssumeRoleWithWebIdentity`** (19/11): CloudTrail cho thấy GitHub gửi `sub` dạng MỚI có ID số `repo:MortimerN4h@159760215/devops-lab@1462580632:ref:refs/heads/main` (chống chiếm tên repo). Đã sửa trust policy chấp nhận cả 2 dạng (biến `github_repo_with_ids`) → `terraform apply` ở `terraform/ci` rồi `gh run rerun --failed`. Mẹo debug OIDC: CloudTrail event `AssumeRoleWithWebIdentity` → `userName` = sub thật.

## 8. Nhật ký / Kiến thức đã học
- 2026-11-17: swap (fallocate/chmod 600/mkswap/swapon, fstab). Build ở nơi khác rồi push ECR, EC2 chỉ pull+chạy. Terraform = tạo hạ tầng, Ansible = cấu hình trong máy.
- 2026-11-17: Lỗi "permission denied ... docker.sock" = phiên chưa nhận nhóm docker sau usermod (không phải security group) → newgrp/SSH lại.
- 2026-11-17: Docker: client/daemon/image/layer/container, port mapping, volume, network compose (gọi nhau bằng tên service), healthcheck + depends_on, multi-stage build, build context (không COPY file ngoài context), cache layer (COPY package*.json trước).
- 2026-11-17: Git: .gitignore (không commit bí mật/tfstate), SSH key, remote/origin, push -u. API: REST, mã trạng thái 200/201/204/400/404/500, JSON lỗi thống nhất, test bằng curl.
- 2026-11-17: Cổng 8080 từng trùng với nginx trên laptop khi forward qua IDE → đổi 18080.
- 2026-11-18: Terraform cơ bản: block terraform/provider/variable/data/resource/output, init → plan → apply, state. IAM: user + access key (dài hạn) vs role (credential tạm, không lưu key) + instance profile; EC2 thuộc về account chứ không thuộc user. Security group (SSH chỉ từ IP của PC, /32). user_data chạy script lúc boot. Đã chuyển sang bastion mới bằng Terraform.
- 2026-11-18: Lỗi docker.sock trên bastion mới do bootstrap chạy qua user_data bằng root ($USER=root) → đã thêm root vào nhóm docker thay vì ubuntu; sửa script (`id -u`). Git: lịch sử rẽ nhánh (divergent) → `git fetch` + `git reset --hard origin/main` (bỏ commit local), hoặc `git pull --rebase` (giữ cả hai). Thêm `dueDate` vào API + UI.
- 2026-11-18: Actions repo private báo "recent account payments have failed" (startup_failure, 0 job) = khóa billing tài khoản GitHub, không phải lỗi code. Chuyển sang repo public mới `devops-lab` (lịch sử sạch, ẩn thông tin công ty/leader/email; `DAILY_REPORT.md` gitignore). `gh` CLI: auth device flow, `gh variable set`, `gh run list/watch/view --log-failed`, `gh workflow run`.
