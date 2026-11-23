# Notely – Go app (React + Gin + Redis)

Cùng sản phẩm, cùng giao diện, cùng hợp đồng API ([`../../API.md`](../../API.md)) như app Node và Python, chỉ khác công nghệ:
**frontend** React (chép nguyên từ `apps/nodejs`, chỉ đổi cổng backend) → **backend** Go/Gin → **db** Redis.

> Mục tiêu file này: biết **file nào quyết định việc build và chạy** một dự án Go, và Redis khác DB "có bảng" ở chỗ nào.
> Các file đó giống nhau ở MỌI dự án Go; code trong `main.go` thì không cần đọc để build/deploy.

## Chạy nhanh

```bash
cd task_week1/apps/go
docker compose up -d --build                              # build 2 image + chạy 4 container
docker compose ps -a                                      # redis "(healthy)", redis-seed "Exited (0)"
BASE_URL=http://localhost:18082 ../../tests/api-test.sh   # 18/18 PASS
# web: http://localhost:18082   (IDE: tab Ports → forward 18082)
```

| Lệnh | Ý nghĩa |
|---|---|
| `docker compose ps -a` | `-a` = cả container **đã dừng**. Không có `-a` thì không thấy `redis-seed` (nó chạy xong là thoát) |
| `docker compose logs redis-seed` | `Seeded 4 notes` (lần đầu) hoặc `already has notes, skipping seed` |
| `docker compose exec redis redis-cli` | vào Redis gõ lệnh (xem mục 5), `exit` để thoát |
| `docker compose up -d --build backend` | build + chạy lại riêng backend (dữ liệu giữ nguyên) |
| `docker compose down -v` | xóa luôn volume `redis-data` → MẤT dữ liệu, lần sau seed lại |

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
│  REDIS_ADDR=redis:6379                                          │
└───────────────────────────────┬────────────────────────────────┘
                                ▼
┌─ redis :6379 ─────────────────────── volume redis-data:/data ──┐
│  key notes:next_id, note:1..N, notes:by_id                      │
└─────────────────────────────────────────────────────────────────┘
        ▲ lần đầu: redis-seed (chạy seed.sh rồi thoát)
```

Chuỗi file quyết định việc kết nối (đổi tên/cổng ở một chỗ thì phải sửa đồng bộ):
`src/api.js` (`/api/...`) → `nginx.conf` (`proxy_pass http://backend:8080`) → `docker-compose.yml`
(service `backend`, `REDIS_ADDR`) → `main.go` (đọc `PORT`, mặc định 8080) → service `redis`.

## 2. File nào cần quan tâm?

Chia 2 loại: **file build/run** (phải hiểu, giống nhau mọi dự án) và **code** (không cần đọc để build/deploy).

### Backend Go – áp dụng cho mọi dự án Go

| File | Loại | Nhiệm vụ |
|---|---|---|
| `go.mod` | **build** | Tên module (`module notes-go`), phiên bản Go tối thiểu (`go 1.25.x`), và thư viện cần dùng (`require`). Tương đương `package.json` / `requirements.txt` |
| `go.sum` | **build** | Mã băm của **từng** thư viện (kể cả thư viện gián tiếp). Lúc tải, Go so mã băm: ai sửa thư viện trên mạng là build lỗi ngay. Giống `package-lock.json` nhưng Go **luôn** có file này |
| `Dockerfile`, `.dockerignore` | **build** | Đóng gói (mục 3) |
| `main.go` | code | Toàn bộ API. Với build/run chỉ cần biết: `package main` + `func main()` = **chương trình chạy được**; biến môi trường nó đọc (`REDIS_ADDR`, `PORT`) |

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

### DB – `db/` (Redis)

| File | Nhiệm vụ |
|---|---|
| `seed.sh` | Thêm 4 note mẫu bằng `redis-cli`. Chạy trong container `redis-seed`, bỏ qua nếu đã có dữ liệu |

Redis **không có** thư mục `/docker-entrypoint-initdb.d/` như Postgres/Mongo, nên phải tự làm bước seed (mục 4).

### Phần nối tất cả

| File | Nhiệm vụ |
|---|---|
| `docker-compose.yml` | 4 container (3 chạy lâu + 1 seed chạy một lần), volume, thứ tự khởi động |
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
      REDIS_ADDR: redis:6379           # main.go đọc bằng os.Getenv("REDIS_ADDR"); host = tên service
    depends_on:
      redis-seed:
        condition: service_completed_successfully   # chờ redis-seed CHẠY XONG và thoát với mã 0

  redis:
    image: redis:7-alpine
    command: ["redis-server", "--appendonly", "yes"]   # ghi mọi thay đổi xuống đĩa (xem dưới)
    volumes:
      - redis-data:/data               # thư mục dữ liệu của image redis
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]               # Redis sẵn sàng thì trả "PONG"
      interval: 5s
      timeout: 5s
      retries: 10

  redis-seed:
    image: redis:7-alpine              # cùng image, chỉ để có sẵn lệnh redis-cli
    entrypoint: ["sh", "/seed.sh"]     # thay lệnh mặc định (redis-server) bằng script seed
    volumes:
      - ./db/seed.sh:/seed.sh:ro
    depends_on:
      redis:
        condition: service_healthy
    restart: "no"                      # chạy một lần: xong là thoát, không khởi động lại

volumes:
  redis-data:
```

So với compose của Node/Python, điểm mới:

- **Container chạy một lần (one-shot job).** `redis-seed` chạy `seed.sh` rồi thoát. Thứ tự:
  `redis` healthy → `redis-seed` chạy, thoát mã 0 → `backend` khởi động → `frontend`.
  Nếu seed lỗi (mã khác 0), backend **không** khởi động, thấy lỗi ngay thay vì app chạy với DB trống.
- **`service_completed_successfully`** – điều kiện thứ ba của `depends_on`, bên cạnh `service_started` (mặc định) và `service_healthy`.
- **`entrypoint:`** ghi đè lệnh khởi động có sẵn của image. Dùng một image chính thức cho việc khác với mục đích gốc của nó.
- **`seed.sh` tự kiểm tra** `EXISTS notes:next_id`: đã có thì bỏ qua. Nhờ vậy chạy lại (`up` lần nữa, deploy lần nữa) không bị nhân đôi dữ liệu.
- **`--appendonly yes`:** mặc định Redis giữ dữ liệu **trong RAM** và chỉ thỉnh thoảng chụp xuống đĩa (snapshot),
  nên tắt đột ngột có thể mất vài phút dữ liệu gần nhất. AOF (append-only file) ghi **từng lệnh thay đổi** xuống `/data` → khởi động lại thì đọc lại.
- Không có user/mật khẩu: image Redis mặc định không yêu cầu. Chỉ an toàn vì Redis **không mở cổng ra ngoài** (không có `ports:`), chỉ container cùng network gọi được.

## 5. Redis khác DB có bảng thế nào

Redis là **key-value store**: mỗi dữ liệu là một **key** (chuỗi tên) với một **kiểu giá trị**. Không có bảng, không có SQL, không có schema.
App tự quyết định cách lưu:

| Key | Kiểu | Lưu gì | Lệnh dùng |
|---|---|---|---|
| `notes:next_id` | STRING | Bộ đếm id | `INCR` → tăng 1 và trả về giá trị mới (an toàn khi nhiều request cùng lúc) |
| `note:5` | HASH (như một object) | `text`, `done` (`1`/`0`), `dueDate` (`""` = null), `createdAt` | `HSET`, `HGETALL`, `DEL` |
| `notes:by_id` | ZSET (tập có thứ tự) | Mọi id, điểm = id | `ZADD`, `ZREM`, `ZREVRANGE` (lấy từ cao xuống = mới nhất trước) |

Tự xem dữ liệu:
```bash
docker compose exec redis redis-cli
KEYS *                        # liệt kê mọi key (chỉ dùng khi học: chậm nếu có hàng triệu key)
HGETALL note:1                # các trường của note 1
ZREVRANGE notes:by_id 0 -1    # mọi id, mới nhất trước
GET notes:next_id
```

Vì không có schema, Redis **không** kiểm tra kiểu dữ liệu: mọi giá trị là chuỗi. `done` là `"1"`/`"0"`, ngày là chuỗi `YYYY-MM-DD`;
backend chịu trách nhiệm kiểm tra và chuyển đổi.

## 6. Code (tham khảo, không cần cho build/deploy)

| | Python/FastAPI | Go/Gin |
|---|---|---|
| Route | `@app.get("/api/notes")` | `api.GET("/notes", func(c *gin.Context) {...})` |
| Lỗi | `raise ApiError(...)` | hàm trả `error`; handler gọi `fail(c, err)` (Go không có exception) |
| JSON | dict | `struct` + tag `` `json:"dueDate"` ``; `*string` (con trỏ) để có `null` |
| DB | SQL | lệnh Redis; `Pipeline` gửi nhiều lệnh trong một lần, `TxPipelined` = `MULTI`/`EXEC` (cùng thành công hoặc không) |
| Dừng | uvicorn tự lo | tự bắt tín hiệu `SIGTERM` (`docker stop`) rồi `srv.Shutdown` cho request đang chạy làm xong |

Giống Python: không dùng `ShouldBindJSON` (cách quen thuộc của Gin) mà tự đọc body, để trả đúng `INVALID_JSON` / `VALIDATION_ERROR` và báo `done must be a boolean`.

## 7. Còn thiếu so với production (làm dần)

1. Frontend là **bản chép** của `apps/nodejs/frontend`: sửa UI phải sửa hai nơi. Có thể build chung một image frontend và chỉ đổi `nginx.conf` lúc chạy (mount).
2. Redis không có mật khẩu (`requirepass`) – chấp nhận được vì không mở cổng, nhưng production nên đặt.
3. `ZREVRANGE notes:by_id 0 -1` lấy **toàn bộ** note: với dữ liệu lớn cần phân trang (`ZREVRANGE notes:by_id 0 19`).
4. Chưa có `package-lock.json` cho frontend (giống Node); chưa giới hạn RAM (`mem_limit`).
