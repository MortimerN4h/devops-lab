# Notely – Python app (Angular + FastAPI + PostgreSQL)

Cùng sản phẩm, cùng giao diện, cùng hợp đồng API ([`../../API.md`](../../API.md)) như app Node, chỉ khác công nghệ:
**frontend** Angular (build ra file tĩnh, phục vụ bằng nginx) → **backend** Python/FastAPI → **db** PostgreSQL.

> Mục tiêu file này: biết **file nào quyết định việc build và chạy** một dự án Python (FastAPI) và Angular.
> Các file đó giống nhau ở MỌI dự án cùng loại; code trong `src/`, `main.py` thì không cần đọc để build/deploy.

## Chạy nhanh

```bash
cd task_week1/apps/python
docker compose up -d --build                              # build 2 image + chạy 3 container
docker compose ps                                         # postgres phải "(healthy)"
BASE_URL=http://localhost:18081 ../../tests/api-test.sh   # 18/18 PASS
# web:     http://localhost:18081          (IDE: tab Ports → forward 18081)
# Swagger: http://localhost:18081/api/docs (tài liệu API tự sinh, bấm thử được)
```

| Lệnh | Ý nghĩa |
|---|---|
| `docker compose up -d --build backend` | build + chạy lại riêng backend (DB giữ nguyên) |
| `docker compose logs backend --tail 50` | 50 dòng log cuối của backend |
| `docker compose exec postgres psql -U notes -d notesdb` | vào DB gõ SQL (`\dt` xem bảng, `\q` thoát) |
| `docker compose down` | xóa container + network (dữ liệu còn trong volume) |
| `docker compose down -v` | xóa luôn volume `pg-data` → MẤT dữ liệu, lần sau chạy lại `init.sql` |

Cổng **18081** (Node dùng 18080) nên chạy được cả hai app cùng lúc.

## 1. Đường đi của một request

```
Trình duyệt ── http://localhost:18081
   ▼  ports "18081:80"
┌─ frontend (nginx) :80 ─────────────────────────────────────────┐
│  /, /main-XXXX.js   → file tĩnh Angular đã build (dist/browser)  │
│  /api/...           → proxy_pass http://backend:8000             │
└───────────────────────────────┬────────────────────────────────┘
                                ▼
┌─ backend (uvicorn + FastAPI) :8000 ────────────────────────────┐
│  DATABASE_URL=postgresql://notes:notes@postgres:5432/notesdb    │
└───────────────────────────────┬────────────────────────────────┘
                                ▼
┌─ postgres :5432 ───────── volume pg-data:/var/lib/postgresql/data ┐
│  database notesdb → bảng notes                                   │
└──────────────────────────────────────────────────────────────────┘
```

Chuỗi file quyết định việc kết nối (đổi tên/cổng ở một chỗ thì phải sửa đồng bộ):
`api.service.ts` (`/api/...`) → `nginx.conf` (`proxy_pass http://backend:8000`) → `docker-compose.yml`
(service `backend`, `DATABASE_URL`) → `Dockerfile` backend (`--port 8000`) → service `postgres`.

## 2. File nào cần quan tâm?

Chia 2 loại: **file build/run** (phải hiểu, giống nhau mọi dự án) và **code** (không cần đọc để build/deploy).

### Backend Python (FastAPI) – áp dụng cho mọi dự án Python web

| File | Loại | Nhiệm vụ |
|---|---|---|
| `requirements.txt` | **build** | Danh sách thư viện + phiên bản. `pip install -r requirements.txt` đọc file này. Tương đương `package.json` của Node. |
| `Dockerfile`, `.dockerignore` | **build** | Cách đóng gói image (giải thích ở mục 3). |
| `main.py` | code | Toàn bộ API. Với build/run chỉ cần biết 2 điều: **tên file + tên biến app** (`main.py` có `app = FastAPI()` → gọi là `main:app`) và **biến môi trường** nó đọc (`DATABASE_URL`). |

Về Python cần biết:

- **Python không "build" ra file chạy** như Java/Go: image chứa trình thông dịch Python + thư viện + file `.py`, chạy thẳng mã nguồn.
- **FastAPI không tự nghe cổng.** Nó chỉ là "ứng dụng"; cần một **server ASGI** là **uvicorn** chạy nó: `uvicorn main:app --host 0.0.0.0 --port 8000`. (Flask/Django thì dùng gunicorn, cùng ý tưởng.)
- **`--host 0.0.0.0`** bắt buộc trong container: mặc định uvicorn nghe `127.0.0.1` = chỉ chính container gọi được, nginx ở container khác sẽ bị từ chối.
- Ở dự án khác bạn có thể gặp **`pyproject.toml`** (+ `poetry.lock` hoặc `uv.lock`) thay cho `requirements.txt`: cùng vai trò (khai báo thư viện), chỉ khác công cụ cài.
- `==` trong `requirements.txt` = **ghim đúng phiên bản** → build hôm nay và tháng sau ra cùng một kết quả.

### Frontend Angular – áp dụng cho mọi dự án Angular

| File | Loại | Nhiệm vụ |
|---|---|---|
| `package.json` | **build** | Thư viện (`@angular/core`...) và script `npm run build` = `ng build`. `devDependencies` (`@angular/cli`, `@angular/build`, `typescript`) chỉ cần lúc build. |
| `package-lock.json` | **build** | Phiên bản CHÍNH XÁC đã cài (chưa có ở repo này – xem mục 6). |
| `angular.json` | **build** | Cấu hình của Angular CLI: file vào, file ra, CSS, cách build (xem bảng dưới). |
| `tsconfig.json`, `tsconfig.app.json` | **build** | Cấu hình trình biên dịch TypeScript (mức kiểm tra `strict`, file nào được biên dịch). Hiếm khi phải sửa. |
| `src/index.html` | **build** | Trang gốc, chứa thẻ `<app-root>` – Angular vẽ toàn bộ giao diện vào thẻ này. |
| `src/main.ts` | **build** | Điểm khởi đầu: `bootstrapApplication(AppComponent)`. |
| `src/styles.css` | code | CSS toàn trang (dùng lại 100% từ bản React). |
| `src/app/**` | code | Component, service... Riêng `api.service.ts` đáng nhớ: **chỗ duy nhất gọi backend** (`/api/...`). |
| `nginx.conf` | **build/run** | Giống Node, chỉ đổi `backend:3000` → `backend:8000`. |
| `Dockerfile`, `.dockerignore` | **build** | Đóng gói. |

**`angular.json` – chỉ cần hiểu mấy dòng này:**

| Khóa | Giá trị | Ý nghĩa |
|---|---|---|
| `builder` | `@angular/build:application` | Bộ build hiện đại của Angular (dùng esbuild, nhanh) |
| `browser` | `src/main.ts` | File code bắt đầu |
| `index` | `src/index.html` | Trang HTML gốc |
| `styles` | `["src/styles.css"]` | CSS toàn cục |
| `outputPath` | `dist` | Thư mục kết quả. Builder này ghi file cho trình duyệt vào **`dist/browser/`** → Dockerfile phải copy đúng thư mục đó |
| `outputHashing` | `all` | Tên file kèm mã hash (`main-ZUEXJTPA.js`): đổi code → đổi tên → trình duyệt không dùng nhầm bản cache cũ |
| `polyfills` | `["zone.js"]` | Thư viện giúp Angular biết khi nào cần vẽ lại giao diện |

Giống React: `npm run build` biến TypeScript + template thành **HTML/CSS/JS thuần** (~200KB). Sau bước này không cần Node nữa, chỉ cần nginx phát file.

### DB – `db/` (PostgreSQL)

| File | Nhiệm vụ |
|---|---|
| `init.sql` | Tạo bảng `notes` + 4 note mẫu. Không có Dockerfile vì dùng nguyên image chính thức `postgres:16-alpine`. |

Khác MongoDB: Postgres cần **schema** – `CREATE TABLE` với kiểu từng cột (`VARCHAR(200)`, `BOOLEAN`, `DATE`, `TIMESTAMPTZ`) và ràng buộc (`NOT NULL`, `DEFAULT`) trước khi thêm dữ liệu. DB tự từ chối dữ liệu sai kiểu.

### Phần nối tất cả

| File | Nhiệm vụ |
|---|---|
| `docker-compose.yml` | 3 container, volume, biến môi trường, thứ tự khởi động. |
| `../../API.md`, `../../tests/api-test.sh` | Hợp đồng chung + bộ test chung (`BASE_URL=http://localhost:18081`). |

## 3. Dockerfile – từng dòng

### `backend/Dockerfile`

```dockerfile
FROM python:3.12-slim                  # nền: Python 3.12 trên Debian rút gọn (~45MB)
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1                 # (1) không tạo file .pyc   (2) in log ngay, không giữ trong bộ đệm
WORKDIR /app                           # tạo + cd vào /app
COPY requirements.txt .                # CHỈ copy danh sách thư viện trước...
RUN pip install --no-cache-dir -r requirements.txt   # ...rồi cài; --no-cache-dir: không giữ file tải về → image nhỏ hơn
COPY main.py .                         # sau đó mới copy code
RUN useradd --create-home --uid 10001 app   # tạo user thường tên "app"
USER app                               # từ đây mọi lệnh + tiến trình chạy bằng user này, KHÔNG phải root
EXPOSE 8000                            # ghi chú cổng (không mở cổng nào)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- **Mẹo cache giống Node:** `requirements.txt` + `pip install` đứng trước `COPY main.py`. Sửa code → layer cài thư viện được dùng lại → build vài giây.
- **Vì sao `-slim` chứ không `-alpine` như Node?** Thư viện Python có phần viết bằng C (như `psycopg[binary]`, `uvloop`) được phát hành sẵn dạng *wheel* cho Linux thường (glibc). Alpine dùng musl → nhiều thư viện phải tự biên dịch → cần cài thêm trình biên dịch, build lâu. Với Python, `-slim` là lựa chọn phổ biến.
- **`PYTHONUNBUFFERED=1`:** không có dòng này, `print`/log có thể bị giữ trong bộ đệm → `docker logs` không thấy gì dù app đang chạy.
- **`USER app`:** nếu app bị tấn công, kẻ tấn công chỉ có quyền user thường trong container. (Bản Node chưa làm – xem README Node mục 5.)
- `CMD` dạng mảng (exec form): uvicorn là tiến trình số 1, nhận đúng tín hiệu tắt từ `docker stop`.

### `frontend/Dockerfile` (multi-stage, giống hệt cấu trúc React)

```dockerfile
# ---- Stage 1 "build": Node + Angular CLI chỉ dùng để build ----
FROM node:22-alpine AS build
WORKDIR /app
ENV NG_CLI_ANALYTICS=false             # Angular CLI không hỏi "có gửi thống kê không?" (trong Docker không ai trả lời được → treo)
COPY package*.json ./
RUN npm install                        # cài cả devDependencies vì cần @angular/cli để build
COPY . .
RUN npm run build                      # = ng build → tạo /app/dist/browser

# ---- Stage 2: image cuối, chỉ nginx + file tĩnh ----
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/browser /usr/share/nginx/html   # khác React: dist/browser chứ không phải dist
EXPOSE 80
```

- So với React chỉ khác 2 dòng: `ENV NG_CLI_ANALYTICS=false` và đường dẫn `dist/browser`. **Mọi frontend build ra file tĩnh (React, Angular, Vue...) đều dùng đúng khuôn này**, chỉ cần biết lệnh build và thư mục kết quả.
- Stage 1 nặng vài trăm MB (`node_modules`), image cuối chỉ ~50MB vì chỉ lấy `dist/browser`.
- `.dockerignore` loại `node_modules`, `dist`, `.angular` (cache build của Angular trên máy).

## 4. `docker-compose.yml` – từng dòng

```yaml
services:
  frontend:
    build: ./frontend                  # build image từ ./frontend/Dockerfile
    ports:
      - "18081:80"                     # bastion:18081 → nginx:80 trong container
    depends_on:
      - backend                        # start backend trước

  backend:
    build: ./backend
    environment:
      # main.py đọc bằng os.getenv("DATABASE_URL")
      # dạng: postgresql://USER:PASSWORD@HOST:PORT/DATABASE   (HOST = tên service "postgres")
      DATABASE_URL: postgresql://notes:notes@postgres:5432/notesdb
    depends_on:
      postgres:
        condition: service_healthy     # chờ Postgres SẴN SÀNG, không chỉ "đã chạy"

  postgres:
    image: postgres:16-alpine          # image có sẵn, không build
    environment:                       # image tự tạo user + database theo 3 biến này ở lần chạy đầu
      POSTGRES_USER: notes
      POSTGRES_PASSWORD: notes         # chỉ dùng local; production đọc từ file .env (không commit)
      POSTGRES_DB: notesdb
    volumes:
      - pg-data:/var/lib/postgresql/data                         # named volume: dữ liệu DB
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro    # bind mount: script tạo bảng + seed
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -U notes -d notesdb"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  pg-data:
```

So với compose của Node, điểm mới:

- **Biến `POSTGRES_*`:** image chính thức đọc chúng để tạo user/database. MySQL có `MYSQL_*` tương tự. Mongo không cần vì mặc định không có mật khẩu.
- **Chuỗi kết nối `DATABASE_URL`:** chứa cả user, mật khẩu, host, cổng, tên DB. Host là **tên service** (`postgres`), không phải `localhost`.
- **`CMD-SHELL` vs `CMD`:** `CMD` chạy thẳng chương trình với từng tham số; `CMD-SHELL` chạy qua `sh -c "<chuỗi>"` – tiện viết một dòng lệnh.
- **`pg_isready -h 127.0.0.1`:** khi chạy `init.sql`, Postgres khởi động một server tạm **chỉ nghe socket nội bộ**, xong mới khởi động lại thật. `pg_isready` không có `-h` kiểm tra qua socket → báo sẵn sàng quá sớm → backend kết nối lúc DB đang khởi động lại → lỗi. Có `-h 127.0.0.1` = kiểm tra qua TCP, đúng đường backend dùng.
- **Đường dẫn dữ liệu khác nhau theo image:** Mongo `/data/db`, Postgres `/var/lib/postgresql/data`, MySQL `/var/lib/mysql`. Mount volume sai chỗ = dữ liệu mất khi xóa container.
- `/docker-entrypoint-initdb.d/`: Postgres chạy file `.sql`/`.sh` trong đó **một lần** khi volume trống. Sửa `init.sql` → `docker compose down -v` để chạy lại.

## 5. Code (tham khảo, không cần cho build/deploy)

| | Node/Express | Python/FastAPI |
|---|---|---|
| Route | `app.get('/api/notes', fn)` | `@app.get("/api/notes")` |
| DB | driver `mongodb` | `psycopg` 3 + connection pool (giữ sẵn ≤5 kết nối) |
| Truy vấn | `notes.find()` | `SELECT * FROM notes ORDER BY id DESC` (dùng `%s`, không ghép chuỗi → chống SQL injection) |
| `id` | chuỗi ObjectId | số BIGINT tự tăng |

Không dùng Pydantic model cho body (cách quen thuộc của FastAPI) vì khi sai dữ liệu FastAPI trả **422**, còn API.md yêu cầu **400** + `{"error": {...}}`.

| | React | Angular |
|---|---|---|
| Component | hàm trả JSX | class `@Component({ selector, template })` |
| State | `useState` | `signal()`; giá trị suy ra `computed()` |
| Vòng lặp / điều kiện | `.map()`, `? :` | `@for`, `@if` |
| Sự kiện | `onClick={fn}` | `(click)="fn()"` |
| State dùng chung | props từ App | service `NotesStore`, lấy bằng `inject()` |

## 6. Còn thiếu so với production (làm dần)

1. Chưa có `package-lock.json` (giống Node) → nên commit file lock + dùng `npm ci`.
2. Mật khẩu Postgres ghi thẳng trong compose → khi deploy sẽ đọc từ `.env` trên server.
3. Chưa giới hạn RAM (`mem_limit`) – thêm khi gộp nhiều app trên một EC2.
