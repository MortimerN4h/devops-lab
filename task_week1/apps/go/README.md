# Notely – Go app (React + Gin + PostgreSQL, Redis cache)

Cùng sản phẩm, cùng giao diện, cùng hợp đồng API ([`../../API.md`](../../API.md)) như app Node và Python, chỉ khác công nghệ:
**frontend** React (chép nguyên từ `apps/nodejs`, chỉ đổi cổng backend) → **backend** Go/Gin → **PostgreSQL** (DB chính) + **Redis** (cache).

> Mục tiêu file này: biết **file nào quyết định việc build và chạy** một dự án Go, và **Redis làm cache** hoạt động thế nào
> (mẫu "cache-aside", cách phổ biến nhất trong thực tế). Code trong `main.go` thì không cần đọc để build/deploy.

## Chạy nhanh

```bash
cd task_week1/apps/go
docker compose up -d --build                              # build 2 image + chạy 4 container
docker compose ps                                         # postgres "(healthy)"
BASE_URL=http://localhost:18082 ../../tests/api-test.sh   # 18/18 PASS
# web: http://localhost:18082   (IDE: tab Ports → forward 18082)
```

| Lệnh | Ý nghĩa |
|---|---|
| `curl -si localhost:18082/api/notes \| grep X-Cache` | Xem request này lấy từ cache (`HIT`) hay từ DB (`MISS`) – mục 5 |
| `docker compose exec redis redis-cli KEYS '*'` | Các bản sao đang nằm trong cache |
| `docker compose exec postgres psql -U notes -d notesdb` | Vào DB gõ SQL (`\dt` xem bảng, `\q` thoát) |
| `docker compose stop redis` | Thử tắt cache: app **vẫn chạy**, chỉ chậm hơn |
| `docker compose down -v` | Xóa luôn volume `pg-data` → MẤT dữ liệu, lần sau chạy lại `init.sql` |

Cổng **18082** (Node 18080, Python 18081) nên chạy được cả ba app cùng lúc.

## 1. Đường đi của một request

```
Trình duyệt ── http://localhost:18082
   ▼  ports "18082:80"
┌─ frontend (nginx) :80 ─────────────────────────────────────────┐
│  /, /assets/index-XXXX.js → file tĩnh React đã build (dist)     │
│  /api/...                 → proxy_pass http://backend:8080      │
└───────────────────────────────┬────────────────────────────────┘
                                ▼
┌─ backend (1 file binary Go, Gin) :8080 ────────────────────────┐
│  DATABASE_URL=postgres://notes:notes@postgres:5432/notesdb      │
│  REDIS_ADDR=redis:6379                                          │
└──────────┬───────────────────────────────────────┬─────────────┘
   1) hỏi cache trước                     2) MISS: đọc DB, rồi lưu bản sao vào cache
           ▼                                       ▼
┌─ redis :6379 (chỉ RAM) ─────────┐   ┌─ postgres :5432 ── volume pg-data ─┐
│  cache:notes, cache:note:<id>   │   │  bảng notes (dữ liệu THẬT)          │
│  mỗi bản sao sống 60 giây       │   │  init.sql: tạo bảng + 4 note mẫu    │
└─────────────────────────────────┘   └─────────────────────────────────────┘
```

Chuỗi file quyết định việc kết nối (đổi tên/cổng ở một chỗ thì phải sửa đồng bộ):
`src/api.js` (`/api/...`) → `nginx.conf` (`proxy_pass http://backend:8080`) → `docker-compose.yml`
(service `backend`, `DATABASE_URL`, `REDIS_ADDR`) → `main.go` (đọc `PORT`, mặc định 8080) → service `postgres` và `redis`.

## 2. File nào cần quan tâm?

Chia 2 loại: **file build/run** (phải hiểu, giống nhau mọi dự án) và **code** (không cần đọc để build/deploy).

### Backend Go – áp dụng cho mọi dự án Go

| File | Loại | Nhiệm vụ |
|---|---|---|
| `go.mod` | **build** | Tên module (`module notes-go`), phiên bản Go tối thiểu (`go 1.25.x`), và thư viện cần dùng (`require`). Tương đương `package.json` / `requirements.txt` |
| `go.sum` | **build** | Mã băm của **từng** thư viện (kể cả thư viện gián tiếp). Lúc tải, Go so mã băm: ai sửa thư viện trên mạng là build lỗi ngay. Giống `package-lock.json` nhưng Go **luôn** có file này |
| `Dockerfile`, `.dockerignore` | **build** | Đóng gói (mục 3) |
| `main.go` | code | Toàn bộ API. Với build/run chỉ cần biết: `package main` + `func main()` = **chương trình chạy được**; biến môi trường nó đọc (`DATABASE_URL`, `REDIS_ADDR`, `PORT`) |

Về Go cần biết:

- **Go biên dịch ra MỘT file binary** chứa sẵn mọi thứ (code + thư viện + runtime). Chạy không cần cài Go, Python hay Node.
  Đây là lý do image cuối chỉ ~18 MB (Node/Python cần cả trình thông dịch).
- **`go.mod` và `go.sum` sinh ra thế nào:** `go mod init <tên>` tạo `go.mod`; `go get <thư viện>@<phiên bản>` thêm vào `require`;
  `go mod tidy` dọn: thêm thư viện còn thiếu, xóa cái không dùng, ghi `go.sum`. Cả hai file **phải commit**.
  (Bastion không cài Go: hai file này được tạo bằng container `golang:1.25-alpine`.)
- **Thư viện gọi bằng đường dẫn**: `github.com/gin-gonic/gin` vừa là tên trong `import` vừa là nơi tải code. Không có "npm registry" trung tâm.
- `// indirect` trong `go.mod` = thư viện mà thư viện của mình cần (gián tiếp).
- **Gin** là web framework (như Express của Node, FastAPI của Python). Khác Python: Go **tự nghe cổng**
  (`http.Server.ListenAndServe`), không cần server riêng như uvicorn.

### Frontend React – chép nguyên từ `apps/nodejs/frontend`

Xem giải thích từng file ở [`../nodejs/README.md`](../nodejs/README.md). Chỉ khác **một dòng** trong `nginx.conf`:
`proxy_pass http://backend:3000` → `http://backend:8080`. Frontend chỉ gọi `/api/...` nên không biết backend viết bằng gì.

### DB – `db/` (PostgreSQL)

| File | Nhiệm vụ |
|---|---|
| `init.sql` | Tạo bảng `notes` + 4 note mẫu. **Giống hệt** app Python (cùng schema). Postgres chạy file này **một lần** khi volume trống |

Redis **không có file nào**: cache bắt đầu rỗng và tự đầy dần theo request. Đây là đặc điểm của cache – mất hết cũng không sao.

### Phần nối tất cả

| File | Nhiệm vụ |
|---|---|
| `docker-compose.yml` | 4 container, volume, thứ tự khởi động |
| `../../API.md`, `../../tests/api-test.sh` | Hợp đồng chung + bộ test chung (`BASE_URL=http://localhost:18082`) |

## 3. Dockerfile – từng dòng

### `backend/Dockerfile` (multi-stage, image cuối KHÔNG có Go)

```dockerfile
# ---- Stage 1 "build": trình biên dịch Go (~300 MB) ----
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./          # chỉ 2 file khai báo thư viện trước...
RUN go mod download            # ...để layer tải thư viện được cache: sửa main.go không phải tải lại
COPY . .                       # rồi mới copy code
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /out/server .

# ---- Stage 2: chỉ binary ----
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
ENV GIN_MODE=release
EXPOSE 8080
ENTRYPOINT ["/server"]
```

| Dòng | Ý nghĩa |
|---|---|
| `go build ... -o /out/server .` | Biên dịch package trong thư mục hiện tại (`.`) thành file `/out/server` |
| `CGO_ENABLED=0` | Không dùng thư viện C của hệ điều hành → binary **tự đủ**, chạy được trên image trống. Bật CGO thì binary cần `libc` của đúng bản Linux đã build |
| `-trimpath` | Bỏ đường dẫn thư mục máy build ra khỏi binary (gọn, không lộ cấu trúc máy build) |
| `-ldflags "-s -w"` | Bỏ thông tin debug → binary nhỏ hơn khoảng 30% |
| `distroless/static-debian12` | Image của Google **gần như trống**: chỉ có chứng chỉ CA, múi giờ, file user. **Không có shell** (`sh`), không `apt`. Kẻ tấn công vào được container cũng không có công cụ gì để dùng |
| `:nonroot` | Image chạy bằng user 65532, không phải root (Python phải tự `useradd`, ở đây có sẵn) |
| `GIN_MODE=release` | Gin tắt log debug và cảnh báo dành cho lúc phát triển |
| `ENTRYPOINT ["/server"]` | Chạy binary. Dạng mảng JSON = chạy thẳng, không qua shell (vì image không có shell) |

Hệ quả của distroless: **không** `docker compose exec backend sh` được. Muốn xem bên trong thì xem log, hoặc tạm đổi stage 2 sang `alpine`.

So sánh 3 backend (image cuối): Node ~280 MB (Node + `node_modules`), Python ~250 MB (Python + thư viện), **Go ~18 MB** (chỉ binary).

### `frontend/Dockerfile`
Giống hệt Node: stage 1 `node:22-alpine` chạy `npm run build`, stage 2 `nginx:alpine` copy `dist/` + `nginx.conf`.

## 4. `docker-compose.yml` – từng dòng

```yaml
services:
  frontend:
    build: ./frontend
    ports:
      - "18082:80"
    depends_on:
      - backend

  backend:
    build: ./backend
    environment:
      DATABASE_URL: postgres://notes:notes@postgres:5432/notesdb # dữ liệu thật
      REDIS_ADDR: redis:6379                                     # cache (bản sao, mất cũng được)
    depends_on:
      postgres:
        condition: service_healthy     # không có DB thì không làm được gì → chờ DB SẴN SÀNG
      redis:
        condition: service_started     # cache: chỉ cần "đã chạy"

  postgres:                            # giống hệt app Python (xem ../python/README.md mục 4)
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: notes
      POSTGRES_PASSWORD: notes         # chỉ dùng local; production đọc từ .env
      POSTGRES_DB: notesdb
    volumes:
      - pg-data:/var/lib/postgresql/data
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -U notes -d notesdb"]
      interval: 5s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7-alpine
    command: ["redis-server", "--save", "", "--appendonly", "no",
              "--maxmemory", "64mb", "--maxmemory-policy", "allkeys-lru"]

volumes:
  pg-data:
```

So với compose của Node/Python, điểm mới:

- **Hai mức `depends_on` khác nhau có chủ đích:** Postgres là dữ liệu thật nên chờ `service_healthy`; Redis chỉ là cache
  nên `service_started` là đủ (code Go cũng chịu được Redis chưa sẵn sàng hoặc chết giữa chừng).
- **`command:` của Redis = cấu hình "cache thuần":**

| Tham số | Ý nghĩa |
|---|---|
| `--save ""` | Tắt snapshot xuống đĩa |
| `--appendonly no` | Tắt AOF (ghi từng lệnh xuống đĩa) |
| `--maxmemory 64mb` | Dùng tối đa 64 MB RAM |
| `--maxmemory-policy allkeys-lru` | Đầy thì **tự xóa key lâu nhất chưa dùng** (LRU = least recently used). Mặc định Redis báo lỗi khi đầy – hợp với DB, không hợp với cache |

  Vì không ghi đĩa nên Redis **không cần volume**: restart là cache rỗng, request đầu tiên đọc lại từ Postgres.
- Redis không mật khẩu, không `ports:` → chỉ container cùng network gọi được.

## 5. Redis làm cache: mẫu "cache-aside"

```
ĐỌC  (GET /api/notes, GET /api/notes/5)
  1. GET cache:notes trong Redis
  2a. Có (HIT)  → trả luôn, KHÔNG đụng Postgres                         X-Cache: HIT
  2b. Không (MISS) → SELECT trong Postgres → SET cache:notes <json> EX 60 → trả   X-Cache: MISS

GHI  (POST, PUT, DELETE)
  1. INSERT/UPDATE/DELETE trong Postgres (nguồn sự thật)
  2. DEL cache:notes cache:note:5      → xóa bản sao đã CŨ; lần đọc sau sẽ MISS và lấy bản mới
```

| Quyết định | Vì sao |
|---|---|
| **Xóa** cache khi ghi, không **sửa** cache | Đơn giản và an toàn: không bao giờ phải tính lại danh sách trong cache cho đúng |
| Mỗi bản sao sống **60 giây** (`EX 60`, xem bằng `TTL cache:notes`) | Lưới an toàn: nếu có đường ghi nào quên xóa cache, dữ liệu cũ cũng chỉ sống tối đa 60 giây |
| Redis lỗi → **coi như MISS**, chỉ ghi log | Cache là để tăng tốc. Cache chết không được làm app chết (thử: `docker compose stop redis`, API vẫn trả 200) |
| Header `X-Cache: HIT/MISS` | Chỉ để học/quan sát. Hệ thống thật (CDN, nginx cache) cũng hay trả header kiểu này |

Thử tận mắt:
```bash
curl -si localhost:18082/api/notes | grep X-Cache        # MISS (cache rỗng)
curl -si localhost:18082/api/notes | grep X-Cache        # HIT  (lấy từ RAM)
docker compose exec redis redis-cli TTL cache:notes      # số giây còn lại trước khi tự hết hạn
curl -s -XPOST localhost:18082/api/notes -H 'Content-Type: application/json' -d '{"text":"x"}'
curl -si localhost:18082/api/notes | grep X-Cache        # MISS (POST vừa xóa bản sao cũ)
```

Với app nhỏ thế này, Postgres trả lời trong vài mili giây nên cache gần như không thấy khác biệt. Cache có giá trị khi
truy vấn **chậm** (nhiều JOIN, tính toán) hoặc **rất nhiều** người đọc cùng một dữ liệu – Redis đỡ tải cho DB.

### Redis làm DB chính được không?

Được, nếu bật ghi đĩa (`--appendonly yes`) – phiên bản đầu của app này làm vậy. Nhưng thường người ta không dùng cho dữ liệu nghiệp vụ:
dữ liệu phải vừa **RAM**, sập có thể mất khoảng 1 giây cuối, không có SQL/schema. Redis làm "kho chính" hợp với session đăng nhập,
hàng đợi, bảng xếp hạng, giới hạn số request.

## 6. Code (tham khảo, không cần cho build/deploy)

| | Python/FastAPI | Go/Gin |
|---|---|---|
| Route | `@app.get("/api/notes")` | `api.GET("/notes", func(c *gin.Context) {...})` |
| Lỗi | `raise ApiError(...)` | hàm trả `error`; handler gọi `fail(c, err)` (Go không có exception) |
| JSON | dict | `struct` + tag `` `json:"dueDate"` ``; `*string` (con trỏ) để có `null` |
| DB | `psycopg` + pool, placeholder `%s` | `pgx` + `pgxpool`, placeholder `$1` (chống SQL injection) |
| Cache | – | `go-redis`: `GET`/`SET ... EX 60`/`DEL` |
| Dừng | uvicorn tự lo | tự bắt tín hiệu `SIGTERM` (`docker stop`) rồi `srv.Shutdown` cho request đang chạy làm xong |

Giống Python: không dùng `ShouldBindJSON` (cách quen thuộc của Gin) mà tự đọc body, để trả đúng `INVALID_JSON` / `VALIDATION_ERROR` và báo `done must be a boolean`.

## 7. Còn thiếu so với production (làm dần)

1. Frontend là **bản chép** của `apps/nodejs/frontend`: sửa UI phải sửa hai nơi. Có thể build chung một image frontend và chỉ đổi `nginx.conf` lúc chạy (mount).
2. Redis không có mật khẩu (`requirepass`) – chấp nhận được vì không mở cổng, nhưng production nên đặt.
3. Nhiều backend cùng chạy: request A xóa cache đúng lúc request B vừa đọc DB cũ và đang ghi vào cache → bản cũ sống tới 60 giây.
   TTL ngắn giới hạn thiệt hại; hệ thống lớn dùng thêm khóa hoặc phiên bản dữ liệu.
4. `GET /api/notes` trả **toàn bộ** note: dữ liệu lớn cần phân trang (và cache theo từng trang).
5. Chưa có `package-lock.json` cho frontend (giống Node); chưa giới hạn RAM (`mem_limit`) cho backend/Postgres.
