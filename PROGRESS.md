# DevOps Lab – Progress & Context (AGENT: ĐỌC FILE NÀY ĐẦU TIÊN)

> Cập nhật file này sau MỖI bước hoàn thành. Session mới: đọc file này, rồi tiếp tục từ "Bước hiện tại".

## 1. Bối cảnh & cách làm việc
- User là người mới với nhiều ngôn ngữ; mục tiêu là **HỌC**, không phải nhận code làm sẵn. Trả lời bằng **tiếng Việt**.
- **User tự chạy lệnh** (build/run/test/git...), agent hướng dẫn + giải thích. Agent chỉ được viết/sửa file source.
- Nhịp độ: mỗi lượt làm NHIỀU việc hơn (gộp nhiều bước liên quan) nhưng VẪN giải thích đầy đủ mọi lệnh/dòng MỚI; lệnh đã giải thích rồi thì nhắc ngắn. Không đưa lệnh nào mà không giải thích.
- Mỗi ngôn ngữ: giải thích file build (vd Java: pom.xml là gì, sinh ra thế nào), Dockerfile từng dòng.
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
- [ ] Bước 3: Python FastAPI + PostgreSQL + Angular (requirements.txt)
- [ ] Bước 4: Go Gin + Redis (go.mod, multi-stage)
- [ ] Bước 5: PHP Laravel + MySQL (composer.json)
- [ ] Bước 6: Java Spring Boot + MySQL (pom.xml, Maven, multi-stage)
- [ ] Bước 7: Java Quarkus + DynamoDB local
- [ ] Bước 8: Ruby on Rails API + PostgreSQL (Gemfile)
- [ ] Bước 9: docker-compose chạy tất cả + Nginx reverse proxy theo subdomain (cục bộ)
- [ ] Bước 11: AWS: ECR, OIDC + IAM role cho GitHub Actions *(làm sớm, ngay sau Node)*
- [ ] Bước 15: GitHub Actions: build + push ECR (mỗi app thêm 1 job), rồi deploy tự động lên EC2
- [ ] Bước 12: Terraform: EC2 + user_data pull ECR + deploy
- [ ] Bước 12b: Ansible (cấu hình EC2: cài docker, pull ECR, chạy compose)
- [ ] Bước 13: Route53 subdomain
- [ ] Bước 14: HTTPS certbot
(Thứ tự có thể điều chỉnh cùng user. Chi phí: destroy tài nguyên AWS sau mỗi buổi thử; stop bastion khi không dùng.)

## 7. Bước hiện tại
Bước 11 (code đã viết, user đang apply): `task_week1/terraform/ci/` = 2 ECR repo (`devops-lab/node-frontend`, `devops-lab/node-backend`, lifecycle giữ 10 image, scan on push) + OIDC provider GitHub + role `devops-lab-github-actions` (trust: chỉ `repo:MortimerN4h/devops-lab:ref:refs/heads/main`; quyền: chỉ push/pull 2 repo). Workflow `.github/workflows/node.yml`: job `test` (compose + api-test) → job `push` (matrix frontend/backend, OIDC, tag `<sha>` + `latest`, cache gha). User cần: `terraform apply`, đặt GitHub repo **variable** `AWS_ROLE_ARN` = output `github_actions_role_arn`, push, xem tab Actions, kiểm tra `aws ecr list-images`. Thêm app mới: thêm tên vào `repositories` trong `variables.tf` + 1 workflow mới.
Sau đó Bước 3 (Python + Angular). `terraform.tfstate` của `ci/` nằm trên bastion (gitignore) – mất là phải import lại.

## 8. Nhật ký / Kiến thức đã học
- 2026-11-17: swap (fallocate/chmod 600/mkswap/swapon, fstab). Build ở nơi khác rồi push ECR, EC2 chỉ pull+chạy. Terraform = tạo hạ tầng, Ansible = cấu hình trong máy.
- 2026-11-17: Lỗi "permission denied ... docker.sock" = phiên chưa nhận nhóm docker sau usermod (không phải security group) → newgrp/SSH lại.
- 2026-11-17: Docker: client/daemon/image/layer/container, port mapping, volume, network compose (gọi nhau bằng tên service), healthcheck + depends_on, multi-stage build, build context (không COPY file ngoài context), cache layer (COPY package*.json trước).
- 2026-11-17: Git: .gitignore (không commit bí mật/tfstate), SSH key, remote/origin, push -u. API: REST, mã trạng thái 200/201/204/400/404/500, JSON lỗi thống nhất, test bằng curl.
- 2026-11-17: Cổng 8080 từng trùng với nginx trên laptop khi forward qua IDE → đổi 18080.
- 2026-11-18: Terraform cơ bản: block terraform/provider/variable/data/resource/output, init → plan → apply, state. IAM: user + access key (dài hạn) vs role (credential tạm, không lưu key) + instance profile; EC2 thuộc về account chứ không thuộc user. Security group (SSH chỉ từ IP của PC, /32). user_data chạy script lúc boot. Đã chuyển sang bastion mới bằng Terraform.
- 2026-11-18: Lỗi docker.sock trên bastion mới do bootstrap chạy qua user_data bằng root ($USER=root) → đã thêm root vào nhóm docker thay vì ubuntu; sửa script (`id -u`). Git: lịch sử rẽ nhánh (divergent) → `git fetch` + `git reset --hard origin/main` (bỏ commit local), hoặc `git pull --rebase` (giữ cả hai). Thêm `dueDate` vào API + UI.
- 2026-11-18: Actions repo private báo "recent account payments have failed" (startup_failure, 0 job) = khóa billing tài khoản GitHub, không phải lỗi code. Chuyển sang repo public mới `devops-lab` (lịch sử sạch, ẩn thông tin công ty/leader/email; `DAILY_REPORT.md` gitignore). `gh` CLI: auth device flow, `gh variable set`, `gh run list/watch/view --log-failed`, `gh workflow run`.
