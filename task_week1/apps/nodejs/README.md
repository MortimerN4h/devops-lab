# Notely – Node.js app (React + Express + MongoDB)

Ứng dụng ghi chú gồm 3 container: **frontend** (React build tĩnh, phục vụ bằng nginx) → **backend**
(Node.js/Express, REST API) → **db** (MongoDB). Hợp đồng API: [`../../API.md`](../../API.md).

## Chạy nhanh

```bash
cd task_week1/apps/nodejs
docker compose up -d --build          # build image + chạy nền 3 container
docker compose ps                     # mongo phải "healthy"
../../tests/api-test.sh               # 18/18 PASS
# mở http://localhost:18080 (trên IDE: tab Ports → forward 18080)
```

| Lệnh | Ý nghĩa |
|---|---|
| `docker compose up -d --build frontend` | chỉ build + chạy lại 1 service (DB giữ nguyên) |
| `docker compose logs backend --tail 50` | 50 dòng log cuối của 1 service |
| `docker compose down` | xóa container + network (dữ liệu còn trong volume) |
| `docker compose down -v` | xóa luôn volume `mongo-data` → MẤT dữ liệu, lần sau seed lại |

## 1. Đường đi của một request

```
Trình duyệt trên laptop
   │  http://localhost:18080           (IDE forward cổng laptop → bastion)
   ▼
Bastion EC2 :18080
   │  ports "18080:80"                 (Docker chuyển cổng host → container)
   ▼
┌─ container frontend (nginx) :80 ───────────────────────────────┐
│  GET /, /assets/*.js  → trả file tĩnh trong /usr/share/nginx/html │
│  GET /api/...         → proxy_pass http://backend:3000          │
└────────────────────────────────┬───────────────────────────────┘
                                 │  network nội bộ "nodejs_default"
                                 ▼   (tên "backend" = DNS do Docker cấp)
┌─ container backend (Node/Express) :3000 ───────────────────────┐
│  route /api/notes → validate → gọi MongoDB                      │
│  MONGO_URL=mongodb://mongo:27017                                │
└────────────────────────────────┬───────────────────────────────┘
                                 ▼
┌─ container mongo :27017 ─────── volume mongo-data:/data/db ────┐
│  database notesdb → collection notes                             │
└────────────────────────────────────────────────────────────────┘
```

Ví dụ mở trang và thấy danh sách note:

1. Trình duyệt `GET /` → nginx trả `index.html` + file JS đã build. **React chạy trong trình duyệt**, không chạy trong container.
2. Code React gọi `fetch('/api/notes')` (`frontend/src/api.js`). Đường dẫn **tương đối** → request lại đi tới `localhost:18080`, tức là tới nginx.
3. nginx thấy URL bắt đầu bằng `/api/` → chuyển tiếp tới `http://backend:3000/api/notes`.
4. Express khớp `app.get('/api/notes')` → `notes.find()` tới Mongo qua `mongodb://mongo:27017`.
5. Mongo trả document → backend đổi `_id` thành `id` (hàm `toNote`) → JSON → nginx → trình duyệt → React vẽ danh sách.

Ba điểm quan trọng:

- **Chỉ frontend mở cổng ra ngoài.** `backend` và `mongo` không có `ports:` → bên ngoài không gọi thẳng được; chỉ container cùng network gọi được. Đây là lý do an toàn.
- **Container gọi nhau bằng tên service** (`backend`, `mongo`), không bằng IP: Compose tạo network riêng có DNS nội bộ. Vì vậy `localhost:27017` (giá trị mặc định trong `server.js`) **không dùng được trong container**: `localhost` của container backend là chính nó. Compose ghi đè bằng biến môi trường `MONGO_URL`; mặc định `localhost` chỉ dùng khi chạy `node server.js` trực tiếp trên máy.
- **Frontend và API cùng một địa chỉ (same origin)** nhờ nginx proxy → trình duyệt không cần biết backend ở đâu, không gặp lỗi CORS, và thay backend khác (Python, Go...) thì frontend giữ nguyên.

Chuỗi file quyết định việc kết nối (đổi tên/cổng ở một chỗ thì phải sửa đồng bộ):
`api.js` (`/api/...`) → `nginx.conf` (`proxy_pass http://backend:3000`) → `docker-compose.yml` (service `backend`, `MONGO_URL`) → `server.js` (`listen(3000)`, `new MongoClient(MONGO_URL)`) → service `mongo`.

## 2. Các file và nhiệm vụ

### Frontend – `frontend/` (React + Vite + nginx)

| File | Nhiệm vụ |
|---|---|
| `package.json` | Khai báo thư viện (`react`, `vite`...) và script: `npm run dev` (chạy thử), `npm run build` (đóng gói). `devDependencies` = chỉ cần lúc build. |
| `vite.config.js` | Cấu hình Vite; plugin `react()` để hiểu JSX. |
| `index.html` | Trang gốc: chỉ có `<div id="root">` + nạp `src/main.jsx`. |
| `src/main.jsx` | Điểm khởi đầu: gắn `<App/>` vào `#root`. |
| `src/App.jsx`, `src/components/*`, `src/lib/dates.js`, `src/App.css` | Giao diện: state, danh sách, form, ô ngày `dd/mm/yyyy`, toast... |
| `src/api.js` | **Chỗ duy nhất gọi backend** – mọi request đi qua `/api/...`. |
| `nginx.conf` | Cấu hình nginx trong container: phục vụ file tĩnh + proxy `/api/` sang backend. |
| `Dockerfile`, `.dockerignore` | Cách đóng gói thành image. |

`npm run build` biến JSX thành **HTML/CSS/JS thuần** trong `dist/`. Sau bước đó không cần Node nữa, chỉ cần web server (nginx) phát file.

### Backend – `backend/` (Node.js + Express)

| File | Nhiệm vụ |
|---|---|
| `package.json` | Thư viện `express` (web framework) và `mongodb` (driver kết nối DB). |
| `server.js` | Toàn bộ API: đọc `PORT`/`MONGO_URL` từ biến môi trường, kết nối Mongo, 6 route, validate (`text`, `done`, `dueDate`), xử lý lỗi JSON thống nhất. |
| `Dockerfile`, `.dockerignore` | Đóng gói. |

### DB – `db/` (MongoDB)

| File | Nhiệm vụ |
|---|---|
| `seed.js` | Dữ liệu mẫu. Không có Dockerfile vì dùng nguyên image chính thức `mongo:7`. |

### Phần nối tất cả

| File | Nhiệm vụ |
|---|---|
| `docker-compose.yml` | 3 container, network, volume, biến môi trường, thứ tự khởi động. |
| `../../API.md` | Hợp đồng chung giữa frontend và mọi backend. |
| `../../tests/api-test.sh` | Kiểm tra backend đúng hợp đồng (`BASE_URL=http://localhost:18080`). |

## 3. Dockerfile – từng dòng

Dockerfile = **công thức tạo image**. Mỗi lệnh tạo một **layer**; Docker cache từng layer: nếu input
của một lệnh không đổi, lần build sau dùng lại kết quả cũ.

### `backend/Dockerfile`

```dockerfile
FROM node:22-alpine            # image nền: Node 22 trên Alpine Linux (~5MB, so với Debian ~80MB)
WORKDIR /app                   # tạo + cd vào /app; mọi lệnh sau chạy ở đây
COPY package*.json ./          # CHỈ copy file khai báo thư viện trước...
RUN npm install --omit=dev     # ...rồi cài (bỏ thư viện dev)
COPY . .                       # sau đó mới copy toàn bộ mã nguồn (build context = backend/)
USER node                      # từ đây chạy bằng user "node" (uid 1000, có sẵn trong image), không phải root
EXPOSE 3000                    # GHI CHÚ "app nghe cổng 3000" – không mở cổng nào cả
CMD ["node", "server.js"]      # lệnh chạy khi container KHỞI ĐỘNG
```

- **Mẹo cache:** copy `package*.json` và `npm install` trước `COPY . .`. Khi chỉ sửa `server.js`, file package không đổi → layer `npm install` được **dùng lại** → build vài giây thay vì cả phút.
- `.dockerignore` loại `node_modules` để `COPY . .` không ghi đè thư viện vừa cài bằng thư mục trên máy (có thể sai hệ điều hành/phiên bản).
- `RUN` chạy **lúc build** (kết quả nằm trong image); `CMD` chạy **lúc container start**.
- `CMD` dạng mảng JSON (exec form) chạy `node` làm tiến trình số 1 → `docker stop` gửi tín hiệu tắt thẳng tới Node. Dạng chuỗi `CMD node server.js` chạy qua `sh -c`, tín hiệu có thể không tới Node.
- **`USER node`:** mặc định container chạy bằng `root`. Nếu app bị khai thác lỗi, kẻ tấn công có quyền root trong container (dễ thoát ra host hơn, ghi được mọi file). Image `node` có sẵn user `node` → chỉ cần 1 dòng. Đặt **sau** `npm install`/`COPY` để các file vẫn thuộc root → app chỉ **đọc** được mã của chính nó, không sửa được. Kiểm tra: `docker compose exec backend whoami` → `node`.
- `EXPOSE` không mở cổng; muốn truy cập từ ngoài phải dùng `ports:` (compose) hoặc `-p` (`docker run`).

### `frontend/Dockerfile` (multi-stage)

```dockerfile
# ---- Stage 1 "build": cần Node + node_modules (hàng trăm MB) chỉ để build ----
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install                # cài cả devDependencies vì cần vite để build
COPY . .
RUN npm run build              # tạo /app/dist (HTML/CSS/JS thuần)

# ---- Stage 2: image cuối cùng, bắt đầu lại từ nginx sạch ----
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf      # thay cấu hình mặc định của nginx
COPY --from=build /app/dist /usr/share/nginx/html   # lấy DUY NHẤT thư mục dist từ stage 1
EXPOSE 80
```

- Mỗi `FROM` bắt đầu một image mới; **chỉ stage cuối cùng thành image kết quả**. Image cuối ~50MB, không chứa Node, mã nguồn hay `node_modules` → nhỏ, pull nhanh, ít lỗ hổng.
- Không có `CMD` vì kế thừa từ `nginx:alpine` (`CMD ["nginx", "-g", "daemon off;"]`).
- `.dockerignore` loại cả `dist` để bản build cũ trên máy không lọt vào image.

### `frontend/nginx.conf`

| Dòng | Ý nghĩa |
|---|---|
| `listen 80;` | nghe cổng 80 bên trong container |
| `root /usr/share/nginx/html; index index.html;` | thư mục web và file mặc định khi vào `/` |
| `location /api/ { proxy_pass http://backend:3000; }` | URL bắt đầu `/api/` → chuyển sang backend. `proxy_pass` **không có đường dẫn phía sau** nên giữ nguyên URL: `/api/notes` → `backend:3000/api/notes` |
| `proxy_set_header Host $host; X-Real-IP $remote_addr;` | cho backend biết domain và IP thật của người dùng (không đặt thì backend chỉ thấy IP của nginx) |
| `location / { try_files $uri /index.html; }` | có file đúng tên thì trả file đó, không thì trả `index.html` – chuẩn cho single-page app |

## 4. `docker-compose.yml` – từng dòng

```yaml
services:                          # danh sách container; tên service = hostname trong network
  frontend:
    build: ./frontend              # build image từ ./frontend/Dockerfile (thư mục này = build context)
    ports:
      - "18080:80"                 # "cổng HOST:cổng CONTAINER" → bastion:18080 → nginx:80
    depends_on:
      - backend                    # start backend trước (chỉ chờ container "đã chạy")

  backend:
    build: ./backend
    environment:
      MONGO_URL: mongodb://mongo:27017   # server.js đọc bằng process.env.MONGO_URL
    depends_on:
      mongo:
        condition: service_healthy       # chờ healthcheck của mongo báo "healthy"

  mongo:
    image: mongo:7                 # dùng image có sẵn trên Docker Hub, không build
    volumes:
      - mongo-data:/data/db        # NAMED VOLUME: dữ liệu nằm ngoài container
      - ./db/seed.js:/docker-entrypoint-initdb.d/seed.js:ro   # BIND MOUNT file trên máy, :ro = chỉ đọc
    healthcheck:
      test: ["CMD", "mongosh", "--quiet", "--eval", "db.adminCommand('ping')"]
      interval: 5s                 # kiểm tra mỗi 5 giây
      timeout: 5s                  # quá 5 giây không trả lời = lỗi
      retries: 10                  # lỗi 10 lần liên tiếp → "unhealthy"

volumes:
  mongo-data:                      # khai báo named volume (Docker quản lý, /var/lib/docker/volumes)
```

- **`build` vs `image`:** `build` = tự build từ Dockerfile; `image` = pull image có sẵn. Compose production ([`../../deploy/docker-compose.yml`](../../deploy/docker-compose.yml)) dùng `image: <ECR URL>` – EC2 chỉ pull, không build.
- **Network:** không cần khai báo – Compose tự tạo `<tên-thư-mục>_default` (ở đây `nodejs_default`) và gắn cả 3 container vào (`docker network ls`).
- **Vì sao cần `condition: service_healthy`:** `depends_on` dạng ngắn chỉ đảm bảo container **đã chạy**, không phải **đã sẵn sàng**. Mongo cần vài giây khởi động; backend kết nối sớm sẽ lỗi và `process.exit(1)`.
- **Named volume vs bind mount:** `mongo-data:` do Docker quản lý, dùng cho dữ liệu cần giữ (xóa container vẫn còn, chỉ `down -v` mới mất). `./db/seed.js:` gắn trực tiếp file trên máy vào container, dùng cho cấu hình/script.
- **`/docker-entrypoint-initdb.d/`:** quy ước của image `mongo` (postgres, mysql cũng có). Khi thư mục dữ liệu **trống**, image chạy mọi file `.js`/`.sh` trong đó → seed chỉ chạy lần đầu.

## 5. Còn thiếu so với production (làm dần)

1. Chưa có `package-lock.json` → mỗi lần build có thể cài phiên bản thư viện khác (`^4.21.0` cho phép 4.x mới hơn). Chuẩn: commit file lock + dùng `npm ci`.
2. ~~Backend chạy bằng `root`~~ → **đã sửa**: `USER node` (mục 3).
3. ~~Chưa có `restart: unless-stopped`~~ → **đã có** trong compose production ([`../../deploy/docker-compose.yml`](../../deploy/docker-compose.yml)); compose local không cần.
