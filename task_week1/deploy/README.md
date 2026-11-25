# Deploy – chạy mọi app trên một server production

Thư mục này là **toàn bộ cấu hình production** của server `devops-app` (EC2 tạo bằng [`../terraform/app`](../terraform/app)).
Server clone repo về `/opt/devops-lab`, rồi chạy compose trong `/opt/devops-lab/task_week1/deploy`.

> Mục tiêu file này: hiểu **một thay đổi đi từ `git push` tới trình duyệt như thế nào**, mỗi file ở đây làm gì,
> và **thêm một app mới** cần làm những bước nào (checklist ở mục 8).

Hiện đang chạy: `https://node.<domain>` (React + Express + MongoDB), `https://python.<domain>` (Angular + FastAPI + PostgreSQL) và `https://go.<domain>` (React + Gin + PostgreSQL, Redis cache; sơ đồ dưới chỉ vẽ hai app đầu).

## 1. Toàn cảnh

```
                              ┌──────────── EC2 devops-app (1 Elastic IP) ─────────────────────────────┐
node.<domain>   ─┐  DNS A     │  edge (nginx:1.27-alpine)  :80 :443   ← cổng DUY NHẤT mở ra Internet    │
python.<domain> ─┴─► cùng IP ─┼─► HTTPS + chọn app theo server_name                                     │
                              │     │                          │                                        │
                              │  network node              network python                               │
                              │     ▼                          ▼                                        │
                              │  node-frontend (nginx)      python-frontend (nginx)                     │
                              │     │ /api                     │ /api                                   │
                              │  node-backend :3000         python-backend :8000                        │
                              │     │                          │                                        │
                              │  node-mongo                 python-postgres                             │
                              └────────────────────────────────────────────────────────────────────────┘
```

- **1 server, 1 IP, nhiều tên miền.** Mọi bản ghi DNS trỏ cùng một IP. Trình duyệt luôn gửi header `Host: python.<domain>`,
  edge so header đó với `server_name` để biết chuyển tới app nào.
- **Mỗi app một network riêng.** Edge nối vào mọi network (nó phải gọi được mọi frontend); các app thì không thấy nhau
  (Python không vào được Mongo của Node).

## 2. File trong thư mục

| File | Vai trò |
|---|---|
| `docker-compose.yml` | Danh sách container production: edge + 3 container mỗi app. Dùng `image:` từ ECR, **không build** |
| `nginx/http/default.conf.template` | Cấu hình edge **trước khi có cert** (chỉ cổng 80) |
| `nginx/https/default.conf.template` | Cấu hình edge **sau khi có cert**: 80 chuyển sang 443, mỗi app một block 443. **Một file chung cho mọi app** |
| `deploy.sh` | Script chạy trên server mỗi lần deploy (mục 5) |
| `.env` *(chỉ có trên server, không commit)* | `REGISTRY`, `DOMAIN`, `NGINX_MODE`, `PYTHON_DB_PASSWORD` |
| `.nginx-hash` *(chỉ có trên server, không commit)* | Mã băm cấu hình nginx lần deploy trước, để biết khi nào phải restart edge |

Ngoài thư mục này, deploy còn dùng: `../apps/*/db/` (file seed/tạo bảng, mount vào DB),
[`.github/actions/deploy-to-server`](../../.github/actions/deploy-to-server/action.yml) và các workflow trong `.github/workflows/`.

## 3. Hai thứ được giao lên server: `git pull` và `docker compose pull`

| | `git pull` | `docker compose pull` |
|---|---|---|
| Kéo từ | GitHub | ECR |
| Kéo cái gì | **Cấu hình**: compose, template nginx, `deploy.sh`, file seed | **Image app** (code đã build sẵn ở GitHub Actions) |
| Khi sửa | `deploy/**`, `apps/*/db/**` | Code trong `apps/*/frontend`, `apps/*/backend` |

Luôn chạy **`git pull` trước**: `docker compose pull` đọc `docker-compose.yml` để biết cần pull image nào,
nên file compose phải là bản mới nhất. Server **không bao giờ build** – chỉ tải image và chạy.

## 4. Hai loại nginx (dễ nhầm)

| | **edge** (thư mục này) | **nginx trong frontend** (`apps/*/frontend/nginx.conf`) |
|---|---|---|
| Số lượng | 1 container cho cả server | 1 cho mỗi app, nằm **trong image** frontend (stage 2 của Dockerfile) |
| Việc | **Reverse proxy**: HTTPS, chọn app theo tên miền, chuyển tiếp | **Web server**: gửi file `dist/` cho trình duyệt; chuyển `/api` sang backend |
| Có file của app? | Không | Có (`dist/` copy vào lúc build) |
| Image | `nginx:1.27-alpine` chính thức, **không Dockerfile**; cấu hình **mount** từ `nginx/` | Tự build từ Dockerfile của frontend |

Edge không biết `/api` là gì: nó chuyển **cả tên miền** sang frontend. Nhờ nginx trong frontend tự lo `/api`,
mỗi app vẫn chạy trọn vẹn **một mình** ở local và trong CI (`apps/*/docker-compose.yml`), không cần edge.

## 5. `docker-compose.yml` – các điểm chính

```yaml
edge:
  image: nginx:1.27-alpine
  container_name: edge                 # tên cố định: hook của certbot gọi "docker exec edge nginx -s reload"
  ports: ["80:80", "443:443"]          # container DUY NHẤT mở cổng ra ngoài
  environment:
    DOMAIN: ${DOMAIN}                  # thay vào ${DOMAIN} trong các file .template
  volumes:
    - ./nginx/${NGINX_MODE:-http}:/etc/nginx/templates:ro   # chọn bộ cấu hình http hoặc https
    - /var/www/certbot:/var/www/certbot:ro                  # nơi certbot đặt file xác minh tên miền
    - /etc/letsencrypt:/etc/letsencrypt:ro                  # cert do certbot tạo trên máy host
  networks: [node, python, go]         # nối vào MỌI network app
```

- **`${VAR}`** lấy từ `.env` cùng thư mục (compose tự đọc). **`${VAR:-http}`** = dùng `http` nếu biến trống.
  **`${VAR:?thông báo}`** = biến thiếu thì **dừng hẳn** (dùng cho mật khẩu Postgres, để không bao giờ chạy với mật khẩu rỗng).
- **Template của image nginx:** lúc container **khởi động**, script có sẵn trong image đổi
  `/etc/nginx/templates/X.template` thành `/etc/nginx/conf.d/X`, thay `${DOMAIN}`. Biến của nginx như `$host` được giữ nguyên.
  → Sửa template thì phải **restart** edge (không phải `reload`), `deploy.sh` tự làm việc này.
- **`aliases: [backend]`** trên `node-backend` và `python-backend`: image frontend gọi `http://backend:<cổng>`.
  Alias chỉ có hiệu lực **trong network của app đó**, nên hai app cùng dùng tên `backend` mà không đụng nhau, và image không phải sửa.
- **`depends_on` + `condition: service_healthy`**: backend chỉ khởi động khi DB đã trả lời healthcheck.
- **`restart: unless-stopped`**: container tự chạy lại khi bị lỗi hoặc khi server khởi động lại.
- **Volume có tên** (`node-mongo-data`, `python-pg-data`): dữ liệu còn nguyên khi container bị tạo lại.
  File seed/`init.sql` **chỉ chạy lần đầu**, khi volume còn trống.

## 6. `deploy.sh` – chạy trên server mỗi lần deploy

```
1. docker compose pull <mọi service *-frontend, *-backend>   image mới nhất từ ECR (DB và edge dùng tag cố định, không pull)
2. docker compose up -d --remove-orphans                       tạo container còn thiếu, tạo lại container có image/cấu hình đổi,
                                                               xóa container của service đã bị bỏ khỏi compose
3. nếu nội dung nginx/ khác lần trước (so mã băm .nginx-hash):
     docker compose run --rm --no-deps edge nginx -t           kiểm tra cấu hình mới trong một container edge TẠM
     docker compose restart edge                                đạt thì mới restart edge thật
4. docker image prune -f                                       xóa image cũ không còn dùng (ổ 20 GB)
```

Vì sao bước 3 cần thiết: compose chỉ so **các dòng trong `docker-compose.yml`**. Sửa **nội dung** file template
thì dòng `volumes:` của edge không đổi, nên `up -d` để yên edge, và edge vẫn chạy cấu hình cũ.
Nếu `nginx -t` báo lỗi, script dừng (`set -e`), edge đang chạy **giữ cấu hình cũ**: không app nào bị sập vì một lỗi gõ.

Script **luôn cập nhật mọi thứ**, không phân biệt app nào vừa đổi, nên chạy hai lần liên tiếp cũng vô hại.

## 7. CI/CD – workflow nào chạy khi nào

| Bạn sửa | Workflow | Các job |
|---|---|---|
| `apps/nodejs/**` | `node.yml` | test → push image ECR → deploy → smoke test `vars.NODE_URL` |
| `apps/python/**` | `python.yml` | test → push image ECR → deploy → smoke test `vars.PYTHON_URL` |
| `tests/**`, `API.md` | cả hai | (đổi hợp đồng API thì test lại mọi app) |
| `deploy/**` | `deploy.yml` | chỉ deploy (image không đổi, không cần build) |

Mọi job deploy dùng chung [composite action `deploy-to-server`](../../.github/actions/deploy-to-server/action.yml):
1. Tìm EC2 có tag `Name=devops-app` đang chạy (không có thì bỏ qua, báo `notice`).
2. Gửi lệnh qua **SSM Run Command** (agent trên server tự hỏi AWS có lệnh không; không SSH, không mở cổng 22, không lưu key):
   `git pull --ff-only` (user `ubuntu`) rồi `bash deploy.sh` (root).
3. Chờ lệnh xong, in log của server vào log GitHub Actions; lệnh lỗi thì job đỏ.

**`concurrency: group: deploy-app-server`** giống nhau ở mọi workflow: mỗi lúc chỉ một deploy chạm vào server.
GitHub chỉ giữ **một** job chờ mỗi nhóm; job chờ cũ hơn bị **huỷ (xám)**. Như vậy là vô hại, vì job deploy chỉ vào hàng chờ
**sau khi** image đã lên ECR, và job chạy sau luôn pull mọi image. **Chỉ cần job deploy cuối cùng xanh.**
Chạy lại deploy bằng tay: tab Actions → `deploy-config` → **Run workflow**.

Quyền của GitHub Actions trên AWS (OIDC, không có access key): xem [`../terraform/ci`](../terraform/ci).
Role chỉ được push vào repo ECR của dự án, và chỉ được gửi lệnh SSM tới instance có tag `Name=devops-app`.

## 8. Checklist thêm một app mới (ví dụ `go`)

**Thứ tự quan trọng: DNS → cert → block 443.** Nếu block 443 trỏ tới cert chưa có, nginx không khởi động được
và **mọi app sập**. (`deploy.sh` sẽ chặn lại ở bước `nginx -t`, nhưng tốt nhất đừng để xảy ra.)

1. **App chạy ở local**: `apps/go/` có Dockerfile + `docker-compose.yml` riêng (cổng 1808x), `api-test.sh` 18/18.
   Frontend gọi backend qua `http://backend:<cổng>` như hai app kia.
2. **ECR**: thêm `go-frontend`, `go-backend` vào `repositories` trong [`../terraform/ci/variables.tf`](../terraform/ci/variables.tf) → `terraform apply`.
   Quyền push tự cập nhật (policy lặp qua mọi repo).
3. **Workflow**: copy `python.yml` → `go.yml`, đổi `APP_DIR`, `IMAGE_PREFIX`, `BASE_URL`, `scope=` cache, tên biến smoke test.
   Tạo repo variable `GO_URL` = `https://go.<domain>`. Push → test + push image xanh (job deploy chưa có gì để làm với Go, vẫn xanh).
4. **DNS**: thêm `aws_route53_record "go"` trong [`../terraform/app/main.tf`](../terraform/app/main.tf) → `terraform plan`
   phải là `1 to add, 0 to destroy` → apply → `dig +short go.<domain>` ra đúng IP.
5. **Cert** (trên server, edge hiện tại đủ dùng vì block cổng 80 phục vụ xác minh cho mọi tên miền):
   ```bash
   sudo certbot certonly --webroot -w /var/www/certbot -d go.<domain> --dry-run
   sudo certbot certonly --webroot -w /var/www/certbot -d go.<domain> --deploy-hook "docker exec edge nginx -s reload"
   sudo certbot certificates
   ```
6. **Compose + edge** (thư mục này):
   - Mật khẩu DB (nếu có) → thêm vào `.env` trên server **trước khi push**: `echo "GO_DB_PASSWORD=$(openssl rand -hex 16)" >> .env`.
   - `docker-compose.yml`: thêm `go-frontend`, `go-backend` (alias `backend`), DB; network `go`; volume; edge thêm `go` vào `networks` và `depends_on`.
   - Thêm block `go.${DOMAIN}` vào **cả** `nginx/https/` và `nginx/http/` (copy block python, đổi 3 chỗ: `server_name`, thư mục cert, `proxy_pass`).
   - Push → `deploy-config` chạy → kiểm tra `curl -s https://go.<domain>/api/health`.

Tên service **phải** kết thúc bằng `-frontend` / `-backend` thì `deploy.sh` mới tự pull image của nó.

## 9. Vận hành trên server

```bash
cd /opt/devops-lab/task_week1/deploy
docker compose ps                                   # trạng thái mọi container
docker compose logs edge --tail 50                  # log edge (lỗi cert, lỗi cấu hình…)
docker compose logs python-backend -f               # theo dõi log trực tiếp (Ctrl+C để thoát)
sudo bash deploy.sh                                 # deploy bằng tay (sau khi git pull)
docker compose exec edge nginx -T | less            # xem cấu hình edge ĐANG chạy (đã thay ${DOMAIN})
sudo certbot certificates                           # danh sách cert + ngày hết hạn
sudo certbot renew --dry-run                        # thử gia hạn (certbot tự gia hạn bằng systemd timer)
```

## 10. Dựng lại server từ đầu

1. [`../terraform/app`](../terraform/app) `terraform apply`. `user_data` cài Docker + certbot, clone repo,
   ghi `.env` (`REGISTRY`, `DOMAIN`, `NGINX_MODE=http`) rồi `docker compose up -d`.
2. Thêm tay vào `.env`: `PYTHON_DB_PASSWORD` (user_data **chưa** ghi biến này – TODO).
3. Xin cert cho từng tên miền (mục 8 bước 5).
4. Đổi `NGINX_MODE=https` trong `.env` → `docker compose up -d edge` (dòng `volumes:` đổi nên compose tạo lại edge).

Dữ liệu DB nằm trên ổ của server: dựng lại server = **mất dữ liệu** (chỉ còn dữ liệu seed).

Bẫy đã gặp: `terraform plan` đòi **tạo lại server** dù chỉ thêm bản ghi DNS. Nguyên nhân: AMI lấy từ tham số SSM "current"
(luôn là bản Ubuntu mới nhất). Đã sửa bằng `lifecycle { ignore_changes = [ami] }`.

## 11. Còn thiếu so với production (làm dần)

- **Backup DB** (dump định kỳ lên S3) – hiện mất server là mất dữ liệu.
- **`user_data` ghi đủ mật khẩu** (hoặc lấy từ SSM Parameter Store / Secrets Manager thay vì `.env`).
- **Deploy theo tag commit** thay vì `latest`, để rollback được bằng cách deploy lại tag cũ.
- **`mem_limit`** cho từng container: nhiều app trên một máy nhỏ, một app ngốn RAM có thể làm sập các app khác.
- **Repo chỉ cần `deploy/`** trên server (`git sparse-checkout`) thay vì clone cả repo.
- **Giám sát**: uptime check bên ngoài, log tập trung (CloudWatch), cảnh báo khi cert sắp hết hạn.
