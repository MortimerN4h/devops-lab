# Notely – Python app (Angular + FastAPI + PostgreSQL)

Cùng sản phẩm, cùng giao diện, cùng hợp đồng API ([`../../API.md`](../../API.md)) như app Node,
chỉ khác công nghệ: **frontend** Angular (build tĩnh, phục vụ bằng nginx) → **backend** Python/FastAPI → **db** PostgreSQL.
Đọc README của app Node trước ([`../nodejs/README.md`](../nodejs/README.md)); file này chỉ ghi những điểm KHÁC.

## Chạy nhanh

```bash
cd task_week1/apps/python
docker compose up -d --build                        # postgres phải "healthy"
BASE_URL=http://localhost:18081 ../../tests/api-test.sh   # 18/18 PASS
# web: http://localhost:18081   |   Swagger (tài liệu API tự sinh): http://localhost:18081/api/docs
```

Cổng **18081** (Node dùng 18080) nên chạy được cả hai app cùng lúc.

## Cấu trúc

```
python/
├── docker-compose.yml        frontend :18081 → backend :8000 → postgres :5432
├── db/init.sql               tạo bảng notes + 4 note mẫu (chạy 1 lần khi volume rỗng)
├── backend/
│   ├── main.py               toàn bộ API (route, validate, lỗi JSON thống nhất)
│   ├── requirements.txt      thư viện Python, ghim đúng phiên bản (==)
│   └── Dockerfile            python:3.12-slim, chạy bằng user thường (không phải root)
└── frontend/                 Angular 19
    ├── package.json          thư viện + lệnh "ng build"
    ├── angular.json          cấu hình build: file vào (src/main.ts), file ra (dist/browser)
    ├── tsconfig*.json        cấu hình TypeScript (strict)
    ├── nginx.conf            giống Node, chỉ đổi backend:3000 → backend:8000
    ├── Dockerfile            multi-stage: node build → nginx
    └── src/
        ├── index.html        chứa thẻ <app-root>
        ├── main.ts           khởi động Angular + đăng ký HttpClient
        ├── styles.css        CSS dùng lại 100% từ bản React
        └── app/
            ├── app.component.ts      trang chính: lọc, tìm kiếm, danh sách
            ├── notes.store.ts        STATE chung (signals) + hành động add/toggle/save/remove
            ├── api.service.ts        gọi /api/... bằng HttpClient
            ├── dates.ts, note.ts     hàm ngày dd/mm/yyyy, kiểu dữ liệu
            └── components/           navbar, hero, composer, note-item, date-input, toasts, footer
```

## Backend: FastAPI khác Express ở đâu?

| | Node/Express | Python/FastAPI |
|---|---|---|
| Server | `app.listen(3000)` trong code | **uvicorn** (ASGI server) chạy object `app`: `uvicorn main:app --port 8000` |
| Route | `app.get('/api/notes', fn)` | decorator `@app.get("/api/notes")` |
| DB driver | `mongodb` | `psycopg` 3 + **connection pool** (giữ sẵn ≤5 kết nối, cho request mượn) |
| Truy vấn | `notes.find()` | SQL: `SELECT * FROM notes ORDER BY id DESC` |
| Lỗi tập trung | middleware 4 tham số | `@app.exception_handler(...)` |
| `id` | chuỗi ObjectId | số (BIGINT tự tăng) – frontend không quan tâm |

Điểm cần chú ý:

- **`async`/`await`**: mọi route là `async def`, truy vấn DB dùng `await` → trong lúc chờ Postgres, uvicorn phục vụ request khác.
- **Không dùng Pydantic model cho body** (cách "chuẩn" của FastAPI) vì khi sai dữ liệu FastAPI trả **422** với JSON riêng; hợp đồng của mình yêu cầu **400** + `{"error": {...}}`. Nên `read_json()` + `validate()` tự kiểm tra, giống hệt Node.
- **SQL injection**: luôn dùng placeholder `%s` / `%(text)s`, KHÔNG ghép chuỗi (`f"... WHERE id = {id}"`). psycopg gửi giá trị tách khỏi câu SQL.
- **snake_case ↔ camelCase**: cột DB `due_date`, `created_at`; JSON `dueDate`, `createdAt` → đổi trong `to_note()`.
- **Swagger UI** tự sinh từ code ở `/api/docs` (đặt dưới `/api` để đi qua được nginx).

## PostgreSQL khác MongoDB ở đâu?

- Mongo không cần định nghĩa trước; Postgres cần **schema**: `CREATE TABLE` với kiểu từng cột (`VARCHAR(200)`, `BOOLEAN`, `DATE`, `TIMESTAMPTZ`) và ràng buộc (`NOT NULL`, `DEFAULT`). DB tự từ chối dữ liệu sai kiểu.
- Image `postgres` tạo user/database từ biến `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, rồi chạy file trong `/docker-entrypoint-initdb.d/` (**chỉ lần đầu**, khi volume rỗng). Sửa `init.sql` → phải `docker compose down -v` để seed lại.
- **Healthcheck `pg_isready -h 127.0.0.1`**: trong lúc chạy `init.sql`, Postgres chỉ nghe qua socket nội bộ, chưa mở TCP. `pg_isready` không có `-h` kiểm tra qua socket → báo "sẵn sàng" quá sớm → backend kết nối lúc Postgres đang khởi động lại → lỗi. Thêm `-h 127.0.0.1` = kiểm tra qua TCP, đúng đường backend dùng.
- Xem dữ liệu trực tiếp: `docker compose exec postgres psql -U notes -d notesdb -c 'SELECT * FROM notes;'`

## Frontend: Angular khác React ở đâu?

| | React | Angular |
|---|---|---|
| Ngôn ngữ | JSX | TypeScript + template HTML |
| Component | hàm trả JSX | class có `@Component({ selector, template })` |
| State | `useState` | **signal**: `signal()`, đọc bằng `x()`, ghi bằng `x.set()` |
| Giá trị suy ra | `useMemo` | `computed()` |
| Truyền dữ liệu | props | `input()`; hai chiều `model()` + `[(value)]` |
| Vòng lặp / điều kiện | `.map()`, `? :` | `@for (...; track id)`, `@if / @else` |
| Sự kiện | `onClick={fn}` | `(click)="fn()"` |
| Gọi API | `fetch` | `HttpClient` (trả Observable → `firstValueFrom` thành Promise) |
| State dùng chung | truyền props qua App | **service** `NotesStore` (`@Injectable`), component lấy bằng `inject()` |
| Build | Vite → `dist/` | Angular CLI (`ng build`) → `dist/browser/` |

- **Selector dạng thuộc tính** (`header[app-navbar]`, `li[app-note-item]`): component chính là thẻ `<header>`/`<li>` đó, không sinh thêm thẻ bọc `<app-navbar>`. Nhờ vậy CSS cũ (`.notes > li`, navbar sticky) chạy y nguyên và HTML hợp lệ (`<ul>` chỉ chứa `<li>`).
- `npm install` của Angular nặng hơn React (~ vài trăm MB trong stage build) nhưng **image cuối chỉ là nginx + ~200KB file tĩnh**: đó là lợi ích của multi-stage.
