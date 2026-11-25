# Notely – .NET app (React + ASP.NET Core + DynamoDB)

Cùng sản phẩm, cùng giao diện, cùng hợp đồng API ([`../../API.md`](../../API.md)) như các app khác, chỉ khác công nghệ:
**frontend** React (chép từ `apps/go`) → **backend** C#/ASP.NET Core (Minimal API) → **db** DynamoDB.

> Mục tiêu file này: biết **file nào quyết định việc build và chạy** một dự án .NET, và **DynamoDB** (NoSQL do AWS quản lý)
> chạy thế nào ở máy local và trên AWS thật – **cùng một code**, chỉ khác biến môi trường.

| Môi trường | DynamoDB dùng | Bật bằng |
|---|---|---|
| Local (`docker-compose.yml` này) và job `test` trong CI | **DynamoDB Local** – container giả lập của AWS, không tốn tiền, không cần quyền AWS | `DYNAMODB_ENDPOINT=http://dynamodb:8000` |
| Production (EC2) | **DynamoDB thật trên AWS** – bảng tạo bằng Terraform, quyền lấy từ IAM role của EC2 (không có khóa) | Không đặt `DYNAMODB_ENDPOINT` |

## Chạy nhanh

```bash
cd task_week1/apps/dotnet
docker compose up -d --build                              # build 2 image + chạy 4 container
docker compose ps -a                                      # dynamodb-init phải "Exited (0)"
BASE_URL=http://localhost:18084 ../../tests/api-test.sh   # 18/18 PASS
# web: http://localhost:18084   (IDE: tab Ports → forward 18084)
```

| Lệnh | Ý nghĩa |
|---|---|
| `docker compose logs dynamodb-init` | `Creating table notes` + `Seeded 4 notes into notes` |
| `docker compose run --rm --entrypoint aws dynamodb-init dynamodb scan --table-name notes` | Đọc toàn bộ bảng bằng AWS CLI (giải thích ở mục 5) |
| `docker compose down` | Dữ liệu **mất** dù không có `-v`: DynamoDB Local chạy `-inMemory`. Lần `up` sau seed lại |

Cổng **18084** (Node 18080, Python 18081, Go 18082, Java 18083).

## 1. Đường đi của một request

```
Trình duyệt ── http://localhost:18084
   ▼  ports "18084:80"
┌─ frontend (nginx) :80 ─────────────────────────────────────────┐
│  /, /assets/index-XXXX.js → file tĩnh React đã build (dist)     │
│  /api/...                 → proxy_pass http://backend:8080      │
└───────────────────────────────┬────────────────────────────────┘
                                ▼
┌─ backend (dotnet Notes.dll: ASP.NET Core + Kestrel) :8080 ─────┐
│  DYNAMODB_ENDPOINT=http://dynamodb:8000   TABLE_NAME=notes      │
└───────────────────────────────┬────────────────────────────────┘
                                ▼  HTTP + JSON (API của AWS)
┌─ dynamodb (DynamoDB Local, chỉ RAM) :8000 ─────────────────────┐
│  bảng "notes", khóa "id"                                       │
└────────────────────────────────────────────────────────────────┘
        ▲ lần đầu: dynamodb-init (AWS CLI chạy db/init.sh: tạo bảng + 4 note mẫu, rồi thoát)

Production: không có 2 container dưới cùng. backend ──HTTPS──► dynamodb.us-east-1.amazonaws.com
```

Chuỗi file quyết định việc kết nối: `src/api.js` (`/api/...`) → `nginx.conf` (`proxy_pass http://backend:8080`)
→ `docker-compose.yml` (service `backend`, `DYNAMODB_ENDPOINT`, `TABLE_NAME`) → `Program.cs` (đọc 2 biến đó) → service `dynamodb`.

## 2. File nào cần quan tâm?

### Backend .NET – áp dụng cho mọi dự án ASP.NET Core

| File | Loại | Nhiệm vụ |
|---|---|---|
| `Notes.csproj` | **build** | File dự án (XML của MSBuild): phiên bản .NET (`net10.0`), cài đặt, gói NuGet. Tương đương `package.json` / `pom.xml` / `go.mod` |
| `Dockerfile`, `.dockerignore` | **build** | Đóng gói (mục 3) |
| `Program.cs` | code | Toàn bộ API (Minimal API: không cần class `Main`, file chạy từ trên xuống). Với build/run chỉ cần biết biến môi trường nó đọc: `DYNAMODB_ENDPOINT`, `TABLE_NAME`, `AWS_REGION` |
| `bin/`, `obj/` | (sinh ra) | Kết quả build. Không commit (giống `target/` của Java) |

Về .NET cần biết:

- **.NET hiện nay chạy trên Linux, không cần Windows hay Visual Studio.** Mọi việc làm bằng lệnh `dotnet`:
  `dotnet new webapi` (tạo dự án), `dotnet add package X` (thêm thư viện), `dotnet run` (chạy thử), `dotnet publish` (build để deploy).
  Bastion không cài .NET: các lệnh chạy trong container `mcr.microsoft.com/dotnet/sdk`.
- **`<Project Sdk="Microsoft.NET.Sdk.Web">`**: chọn "bộ công cụ" Web = có sẵn ASP.NET Core, web server **Kestrel**, routing, JSON.
  Không cần khai báo thư viện web như `spring-boot-starter-web`.
- **NuGet** = kho thư viện của .NET (như npm, Maven Central). `dotnet add package AWSSDK.DynamoDBv2` tự ghi dòng
  `<PackageReference ... Version="4.1.0.3" />` vào `.csproj`. Phiên bản được **ghim** sẵn trong file.
- **Giống Java:** C# biên dịch ra **IL** (bytecode, file `.dll`), runtime .NET dịch dần ra mã máy lúc chạy.
  Build cần **SDK**, chạy chỉ cần **runtime** (`aspnet`) → hai stage của Dockerfile.
- **`InvariantGlobalization`**: bỏ dữ liệu ngôn ngữ/vùng (ICU) → ngày giờ, số luôn định dạng một kiểu, và chạy được trên Alpine (nhỏ) không cần cài ICU.
- So với Spring Boot: khởi động ~1 giây (Spring ~10 giây), RAM ~60 MB (Spring ~220 MB).

### Frontend React – chép từ `apps/go/frontend`

Xem giải thích ở [`../nodejs/README.md`](../nodejs/README.md). `nginx.conf` giữ nguyên `backend:8080` (cùng cổng với Go).

### DB – `db/` (DynamoDB)

| File | Nhiệm vụ |
|---|---|
| `init.sh` | Chờ DynamoDB sẵn sàng → **tạo bảng** nếu chưa có → **thêm 4 note mẫu** nếu bảng trống. Dùng AWS CLI. **Cùng một script** cho local (container `dynamodb-init`) và production (chạy một lần từ bastion) |

### Phần nối tất cả

| File | Nhiệm vụ |
|---|---|
| `docker-compose.yml` | 4 container (3 chạy lâu + 1 init chạy một lần) |
| `../../API.md`, `../../tests/api-test.sh` | Hợp đồng chung + bộ test chung (`BASE_URL=http://localhost:18084`) |

## 3. Dockerfile – từng dòng

### `backend/Dockerfile`

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build   # SDK: compiler + NuGet (image của Microsoft, registry mcr.microsoft.com)
WORKDIR /src
COPY Notes.csproj .
RUN dotnet restore                                        # tải gói NuGet → layer riêng, cache tới khi .csproj đổi
COPY . .
RUN dotnet publish -c Release --no-restore -o /out        # biên dịch Release + gom mọi file cần để chạy vào /out

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine          # chỉ runtime ASP.NET Core
WORKDIR /app
COPY --from=build /out .
USER $APP_UID                                             # user không phải root có sẵn trong image (1654)
EXPOSE 8080
ENTRYPOINT ["dotnet", "Notes.dll"]
```

| Dòng | Ý nghĩa |
|---|---|
| `dotnet restore` | Cùng ý tưởng `npm install`, `go mod download`, `mvn dependency:go-offline` |
| `publish -c Release` | `-c Release`: tối ưu, bỏ thông tin debug. `--no-restore`: gói đã tải ở bước trên. Kết quả: `Notes.dll` + các `.dll` thư viện + file cấu hình |
| `USER $APP_UID` | Từ .NET 8, image chính thức có sẵn user thường `app`. Không phải `useradd` như Python/Java |
| `ENTRYPOINT ["dotnet", "Notes.dll"]` | Runtime `dotnet` chạy file IL `Notes.dll` (giống `java -jar app.jar`) |
| Cổng 8080 | Image đặt sẵn `ASPNETCORE_HTTP_PORTS=8080`. Kestrel nghe `0.0.0.0` (mọi địa chỉ) nên container khác gọi được |

Image backend ~180 MB (runtime ~110 MB + app + AWS SDK).

## 4. `docker-compose.yml` – từng dòng

```yaml
services:
  frontend:
    build: ./frontend
    ports:
      - "18084:80"
    depends_on:
      - backend

  backend:
    build: ./backend
    environment:
      DYNAMODB_ENDPOINT: http://dynamodb:8000   # có biến này = dùng DynamoDB Local
      TABLE_NAME: notes
    depends_on:
      dynamodb-init:
        condition: service_completed_successfully   # bảng đã tạo + seed xong

  dynamodb:
    image: amazon/dynamodb-local:3.3.0       # bản giả lập của AWS
    command: ["-jar", "DynamoDBLocal.jar", "-inMemory", "-sharedDb"]

  dynamodb-init:
    image: amazon/aws-cli:2.42.3             # image chính thức của AWS CLI
    entrypoint: ["sh", "/init.sh"]           # thay lệnh mặc định "aws" bằng script
    environment:
      AWS_ENDPOINT_URL: http://dynamodb:8000 # AWS CLI v2 gửi mọi lệnh tới địa chỉ này thay vì AWS
      AWS_REGION: us-east-1
      AWS_ACCESS_KEY_ID: local               # DynamoDB Local nhận giá trị bất kỳ, nhưng CLI bắt buộc phải có
      AWS_SECRET_ACCESS_KEY: local
      TABLE_NAME: notes
    volumes:
      - ./db/init.sh:/init.sh:ro
    depends_on:
      - dynamodb
    restart: "no"
```

Điểm mới:

- **`-inMemory`**: DynamoDB Local giữ dữ liệu trong RAM, **mất khi container dừng**. Chấp nhận được vì đây chỉ là môi trường
  dev/test và `dynamodb-init` tự seed lại. (Muốn giữ dữ liệu: `-dbPath` + volume, nhưng phải xử lý quyền ghi thư mục.)
- **`-sharedDb`**: bản thật tách dữ liệu theo region + tài khoản; bản local gộp chung để credential giả nào cũng thấy cùng bảng.
- **Không có healthcheck cho DynamoDB Local** (image không có `curl`), nên `init.sh` **tự chờ** bằng vòng `until aws dynamodb list-tables`.
  `depends_on` mặc định chỉ chờ container **đã khởi động**, không chờ **sẵn sàng** – lần đầu viết thiếu vòng chờ, init lỗi
  `Could not connect to the endpoint URL`.
- **Container one-shot** `dynamodb-init` + `service_completed_successfully`: giống `redis-seed` từng có ở app Go.
- **`AWS_ENDPOINT_URL`**: biến chuẩn mà AWS CLI v2 và nhiều SDK hiểu. Backend .NET thì đọc biến riêng `DYNAMODB_ENDPOINT` (xem `Program.cs`).

## 5. DynamoDB khác DB SQL thế nào

**DynamoDB** là NoSQL key-value/document do **AWS quản lý hoàn toàn**: không có server để cài, không chọn RAM/ổ đĩa,
tự sao lưu và mở rộng; trả tiền theo số request (`PAY_PER_REQUEST`) hoặc theo công suất đặt trước.
Không có bản cài lên server của mình – chỉ có **bản giả lập** để dev.

| | PostgreSQL / MySQL | DynamoDB |
|---|---|---|
| Schema | Khai báo mọi cột (`CREATE TABLE`) | Chỉ khai báo **khóa** (`id`); thuộc tính khác tự do, mỗi item có thể khác nhau |
| Khóa tự tăng | `AUTO_INCREMENT` / `IDENTITY` | **Không có** → app tự tạo id. Ở đây: **UUID v7** (bắt đầu bằng thời gian tạo, nên sắp xếp id = sắp xếp theo thời gian) |
| Truy vấn | SQL bất kỳ, `ORDER BY` | Theo **khóa** (`GetItem`), hoặc `Scan` (đọc cả bảng), hoặc `Query` trên index. **Không có `ORDER BY`** → app tự sắp xếp |
| Kiểu dữ liệu | Theo cột | Mỗi giá trị tự ghi kiểu: `{"S": "chuỗi"}`, `{"BOOL": true}`, `{"N": "5"}` |
| Gọi bằng | Driver + kết nối TCP riêng | **HTTP API của AWS** (như mọi dịch vụ AWS), có chữ ký bằng credential |

Các lệnh dùng trong code:

| Route | Lệnh DynamoDB |
|---|---|
| `GET /api/notes` | `Scan` (lặp theo trang 1 MB, `LastEvaluatedKey`) rồi sắp xếp trong app |
| `GET /api/notes/{id}` | `GetItem` theo khóa |
| `POST` | `PutItem` |
| `PUT` | `UpdateItem` + `ConditionExpression "attribute_exists(id)"` (không có điều kiện này, UpdateItem sẽ **tạo mới** item không tồn tại) |
| `DELETE` | `DeleteItem` + cùng điều kiện → không tồn tại thì lỗi `ConditionalCheckFailed` → 404 |

Tự đọc bảng local:
```bash
docker compose run --rm --entrypoint aws dynamodb-init dynamodb scan --table-name notes
```
`run --rm dynamodb-init` tạo một container **tạm** của service `dynamodb-init` (có sẵn AWS CLI + biến trỏ tới DynamoDB Local),
`--rm` xóa nó khi xong. `--entrypoint aws` thay `sh /init.sh` bằng chương trình `aws`, và phần còn lại (`dynamodb scan ...`) là tham số.
Kết quả là JSON có kiểu của từng giá trị (`"S"`, `"BOOL"`).

## 6. Production: DynamoDB thật trên AWS

Cần thêm (làm ở bước deploy):

1. **Terraform tạo bảng** `aws_dynamodb_table` (`billing_mode = PAY_PER_REQUEST`, `hash_key = "id"`).
2. **Quyền IAM** cho role `devops-app-role` của EC2: `GetItem`, `PutItem`, `UpdateItem`, `DeleteItem`, `Scan` – **chỉ trên ARN của bảng này**.
3. **IMDS hop limit = 2** trên EC2: container lấy credential của instance role qua IMDS (`169.254.169.254`). Request từ container
   đi qua thêm một "bước" mạng (bridge của Docker), mặc định hop limit = 1 thì gói tin bị bỏ → SDK báo không tìm thấy credential.
4. Compose production: backend chỉ có `TABLE_NAME` + `AWS_REGION`, **không** `DYNAMODB_ENDPOINT`, **không** container DynamoDB.
5. Seed một lần từ bastion: `TABLE_NAME=<tên bảng> AWS_REGION=us-east-1 sh db/init.sh` (không đặt `AWS_ENDPOINT_URL` → CLI gọi AWS thật).

Muốn chạy **local trỏ vào AWS thật** (thử bản thật mà không đụng production): dùng một bảng dev riêng, bỏ `DYNAMODB_ENDPOINT`,
và truyền credential vào container (hoặc hop limit 2 trên bastion).

## 7. Code (tham khảo, không cần cho build/deploy)

| | Java/Spring | .NET Minimal API |
|---|---|---|
| Route | `@GetMapping("/notes")` trên method | `app.MapGet("/api/notes", async (...) => ...)` |
| Dependency injection | constructor | tham số của handler: `(IAmazonDynamoDB db)` – đăng ký bằng `AddSingleton` |
| Route không tồn tại | `NoResourceFoundException` | `app.MapFallback(...)` (bắt cả sai method) |
| Lỗi 500 | `@ExceptionHandler(Exception.class)` | `app.UseExceptionHandler(...)` |
| JSON | Jackson | `System.Text.Json` – tự đổi `DueDate` → `dueDate` (camelCase) |

Như các app khác: không dùng tham số kiểu `NoteInput` (cách quen thuộc của Minimal API) mà tự đọc body,
để trả đúng `INVALID_JSON` / `VALIDATION_ERROR` của API.md.

## 8. Còn thiếu so với production (làm dần)

1. `Scan` đọc **cả bảng** mỗi lần liệt kê: tốn tiền và chậm khi bảng lớn. Cách DynamoDB: thiết kế khóa/index (GSI) theo đúng câu hỏi cần trả lời rồi dùng `Query`.
2. DynamoDB Local `-inMemory`: dữ liệu dev mất mỗi lần dừng.
3. Frontend là bản chép của `apps/go/frontend`; chưa có `package-lock.json`.
4. Chưa có unit test (xUnit) và healthcheck kiểm tra kết nối DynamoDB.
