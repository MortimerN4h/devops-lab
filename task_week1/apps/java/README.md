# Notely – Java app (Angular + Spring Boot + MySQL)

Cùng sản phẩm, cùng giao diện, cùng hợp đồng API ([`../../API.md`](../../API.md)) như các app khác, chỉ khác công nghệ:
**frontend** Angular (chép nguyên từ `apps/python`, chỉ đổi cổng backend) → **backend** Java/Spring Boot → **db** MySQL.

> Mục tiêu file này: biết **file nào quyết định việc build và chạy** một dự án Java (Maven + Spring Boot),
> và MySQL khác PostgreSQL ở đâu. Code trong `src/main/java/` thì không cần đọc để build/deploy.

## Chạy nhanh

```bash
cd task_week1/apps/java
docker compose up -d --build                              # lần đầu lâu (~3-5 phút): Maven tải thư viện
docker compose ps                                         # mysql phải "(healthy)" (mất ~30 giây lần đầu)
BASE_URL=http://localhost:18083 ../../tests/api-test.sh   # 18/18 PASS
# web: http://localhost:18083   (IDE: tab Ports → forward 18083)
```

| Lệnh | Ý nghĩa |
|---|---|
| `docker compose logs backend --tail 30` | Log Spring Boot: dòng `Started NotesApplication in X seconds` = đã sẵn sàng |
| `docker compose exec mysql mysql -u notes -pnotes notesdb` | Vào MySQL gõ SQL (`SHOW TABLES;`, `SELECT * FROM notes;`, `exit`) |
| `docker stats --no-stream` | RAM từng container: MySQL ~450 MB, Spring Boot ~220 MB (nặng nhất trong các app) |
| `docker compose down -v` | Xóa luôn volume `mysql-data` → MẤT dữ liệu, lần sau chạy lại `init.sql` |

Cổng **18083** (Node 18080, Python 18081, Go 18082).

## 1. Đường đi của một request

```
Trình duyệt ── http://localhost:18083
   ▼  ports "18083:80"
┌─ frontend (nginx) :80 ─────────────────────────────────────────┐
│  /, /main-XXXX.js   → file tĩnh Angular đã build (dist/browser)  │
│  /api/...           → proxy_pass http://backend:8080             │
└───────────────────────────────┬────────────────────────────────┘
                                ▼
┌─ backend (java -jar app.jar: Spring Boot + Tomcat nhúng) :8080 ┐
│  SPRING_DATASOURCE_URL=jdbc:mysql://mysql:3306/notesdb          │
└───────────────────────────────┬────────────────────────────────┘
                                ▼
┌─ mysql :3306 ─────────────────── volume mysql-data:/var/lib/mysql ┐
│  database notesdb → bảng notes                                    │
└───────────────────────────────────────────────────────────────────┘
```

Chuỗi file quyết định việc kết nối: `api.service.ts` (`/api/...`) → `nginx.conf` (`proxy_pass http://backend:8080`)
→ `docker-compose.yml` (service `backend`, `SPRING_DATASOURCE_*`) → `application.properties` (cổng mặc định 8080) → service `mysql`.

## 2. File nào cần quan tâm?

Chia 2 loại: **file build/run** (phải hiểu, giống nhau mọi dự án) và **code** (không cần đọc để build/deploy).

### Backend Java (Maven + Spring Boot) – áp dụng cho mọi dự án Spring Boot

| File | Loại | Nhiệm vụ |
|---|---|---|
| `pom.xml` | **build** | "Project Object Model": tên dự án, phiên bản Java, thư viện, cách đóng gói. Maven đọc file này. Tương đương `package.json` / `go.mod` |
| `src/main/resources/application.properties` | **run** | Cấu hình lúc chạy: kết nối DB, cổng, cách Hibernate xử lý bảng… **Mọi dòng có thể ghi đè bằng biến môi trường** (xem dưới) |
| `Dockerfile`, `.dockerignore` | **build** | Đóng gói (mục 3) |
| `src/main/java/**` | code | Class Java. Với build/run chỉ cần biết class có `@SpringBootApplication` + `main()` là **điểm bắt đầu** |
| `target/` | (sinh ra) | Kết quả build: `target/app.jar`. Không commit (giống `dist/`, `node_modules/`) |

**Maven và `pom.xml` – cần biết:**

- **Maven** là công cụ build của Java: đọc `pom.xml` → tải thư viện từ **Maven Central** (kho chung, như npm registry) về `~/.m2`
  → biên dịch `.java` thành `.class` → đóng gói thành `.jar`. (Đối thủ: **Gradle**, file `build.gradle`; cùng vai trò.)
- **Thư viện có "tọa độ"** `groupId:artifactId:version`, ví dụ `com.mysql:mysql-connector-j`. Dự án này cũng có tọa độ riêng `lab:notes:1.0.0`.
- **`<parent>spring-boot-starter-parent`**: Spring Boot đã chọn sẵn phiên bản **tương thích nhau** cho hàng trăm thư viện,
  nên các `<dependency>` bên dưới **không ghi phiên bản**. Muốn nâng Spring Boot chỉ cần đổi một dòng `<version>3.5.0</version>`.
- **"Starter"** = một dependency kéo theo cả bộ: `spring-boot-starter-web` = Spring MVC + **Tomcat nhúng** (web server) + Jackson (JSON);
  `spring-boot-starter-data-jpa` = Hibernate + HikariCP (connection pool).
- **`<scope>runtime</scope>`**: driver MySQL chỉ cần lúc **chạy**, code không gọi trực tiếp nên không cần lúc biên dịch.
- **`spring-boot-maven-plugin`**: gói code + **mọi thư viện** vào **một "fat jar"** chạy được bằng `java -jar app.jar`.
- `pom.xml` sinh ra thế nào: thường tạo dự án ở **start.spring.io** (chọn Java, Spring Boot, dependency → tải zip có sẵn `pom.xml`,
  thư mục `src/`, và **Maven Wrapper** `mvnw` – script tự tải đúng phiên bản Maven). Dự án này viết `pom.xml` bằng tay và build bằng image `maven`, nên không cần `mvnw`.
- **Cấu trúc thư mục là quy ước bắt buộc** của Maven: code ở `src/main/java/`, cấu hình ở `src/main/resources/`, test ở `src/test/java/`.
  Tên thư mục con theo **package**: `package lab.notes;` → `src/main/java/lab/notes/`.

**Java chạy thế nào:** `javac` biên dịch `.java` thành **bytecode** (`.class`) – không phải mã máy như Go. Lúc chạy, **JVM**
(Java Virtual Machine, có trong JRE) đọc bytecode và dịch dần ra mã máy. Vì vậy: build cần **JDK** (có trình biên dịch),
chạy chỉ cần **JRE** (nhỏ hơn) – đúng hai stage của Dockerfile.

**`application.properties` và biến môi trường:** Spring Boot cho biến môi trường **ghi đè** file cấu hình theo quy tắc
`spring.datasource.url` → `SPRING_DATASOURCE_URL` (dấu chấm thành gạch dưới, viết hoa). Nhờ vậy cùng một image chạy được
ở local, CI và production – chỉ khác biến môi trường trong compose. Các dòng đáng nhớ:

| Dòng | Ý nghĩa |
|---|---|
| `spring.datasource.url=jdbc:mysql://...?connectionTimeZone=UTC` | Chuỗi kết nối **JDBC** (chuẩn kết nối DB của Java): `jdbc:<loại DB>://host:cổng/database` |
| `spring.jpa.hibernate.ddl-auto=none` | Hibernate **không** tự tạo/sửa bảng – bảng do `init.sql` tạo. (`update`/`create` tiện lúc học nhưng nguy hiểm ở production: có thể xóa/đổi cột) |
| `spring.jpa.open-in-view=false` | Không giữ kết nối DB suốt lúc trả JSON (mặc định bật + in cảnh báo) |
| `server.shutdown=graceful` | `docker stop` → làm nốt request đang chạy rồi mới tắt (Go phải tự viết, Spring có sẵn) |

### Frontend Angular – chép nguyên từ `apps/python/frontend`

Xem giải thích từng file ở [`../python/README.md`](../python/README.md). Chỉ khác **một dòng** trong `nginx.conf`: `backend:8000` → `backend:8080`.

### DB – `db/` (MySQL)

| File | Nhiệm vụ |
|---|---|
| `init.sql` | Tạo bảng `notes` + 4 note mẫu. MySQL chạy file này **một lần** khi volume trống (cùng cơ chế `/docker-entrypoint-initdb.d/` như Postgres) |

### Phần nối tất cả

| File | Nhiệm vụ |
|---|---|
| `docker-compose.yml` | 3 container, volume, biến môi trường, thứ tự khởi động |
| `../../API.md`, `../../tests/api-test.sh` | Hợp đồng chung + bộ test chung (`BASE_URL=http://localhost:18083`) |

## 3. Dockerfile – từng dòng

### `backend/Dockerfile` (multi-stage: JDK + Maven để build, chỉ JRE để chạy)

```dockerfile
FROM maven:3.9-eclipse-temurin-21 AS build      # Maven 3.9 + JDK 21 (Temurin = bản OpenJDK miễn phí của Eclipse)
WORKDIR /src
COPY pom.xml .
RUN mvn -B -q dependency:go-offline             # tải MỌI thư viện trong pom.xml → layer riêng, cache tới khi pom.xml đổi
COPY src ./src
RUN mvn -B -q package -DskipTests               # biên dịch + đóng gói → target/app.jar

FROM eclipse-temurin:21-jre-alpine              # chỉ JRE: chạy được Java, không biên dịch được
RUN addgroup -S app && adduser -S -G app -u 10001 app
WORKDIR /app
COPY --from=build /src/target/app.jar app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]
```

| Dòng | Ý nghĩa |
|---|---|
| `mvn -B -q` | `-B` batch mode: không hỏi gì, log không màu (hợp với CI). `-q` quiet: chỉ in lỗi |
| `dependency:go-offline` | Cùng ý tưởng `COPY package.json` → `npm install` và `COPY go.mod` → `go mod download`: sửa code không phải tải lại thư viện |
| `package` | Một "phase" của Maven: chạy lần lượt `compile` → `test` → `package`. `-DskipTests` bỏ bước test (dự án chưa có unit test; test API chạy trong CI) |
| `eclipse-temurin:21-jre-alpine` | JRE nhỏ hơn JDK khoảng một nửa. Không dùng distroless như Go được dễ dàng vì Java cần JVM |
| `adduser ... app` / `USER app` | Không chạy bằng root (giống Python) |
| `-XX:MaxRAMPercentage=75` | JVM tự chọn kích thước heap theo **RAM của container** (75%). Mặc định chỉ 25% – lãng phí khi container có giới hạn RAM |

Image backend ~400 MB (JRE ~200 MB + fat jar ~60 MB + Alpine), lớn nhất trong các app. RAM lúc chạy ~220 MB – Java "nặng" cả lúc khởi động (~10 giây) lẫn RAM.

### `frontend/Dockerfile`
Giống hệt Python: stage 1 `node:22-alpine` + Angular CLI build, stage 2 `nginx:alpine` copy `dist/browser` + `nginx.conf`.

## 4. `docker-compose.yml` – từng dòng

```yaml
services:
  frontend:
    build: ./frontend
    ports:
      - "18083:80"
    depends_on:
      - backend

  backend:
    build: ./backend
    environment:                        # ghi đè application.properties
      SPRING_DATASOURCE_URL: jdbc:mysql://mysql:3306/notesdb?connectionTimeZone=UTC   # host = tên service "mysql"
      SPRING_DATASOURCE_USERNAME: notes
      SPRING_DATASOURCE_PASSWORD: notes
    depends_on:
      mysql:
        condition: service_healthy

  mysql:
    image: mysql:8.4                    # 8.4 = dòng LTS (hỗ trợ dài hạn) hiện tại
    environment:                        # image tự tạo database + user ở lần chạy đầu
      MYSQL_DATABASE: notesdb
      MYSQL_USER: notes
      MYSQL_PASSWORD: notes
      MYSQL_ROOT_PASSWORD: rootpass     # tài khoản quản trị (image bắt buộc phải có)
    volumes:
      - mysql-data:/var/lib/mysql                                # thư mục dữ liệu của MySQL
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -u notes -pnotes --silent"]
      interval: 5s
      timeout: 5s
      retries: 20
      start_period: 30s

volumes:
  mysql-data:
```

So với Python (PostgreSQL), điểm mới:

- **Biến `MYSQL_*`** thay cho `POSTGRES_*`. MySQL tách **user quản trị** (`root`, bắt buộc có mật khẩu) và **user của app** (`notes`, chỉ có quyền trên `notesdb`). App không bao giờ dùng root.
- **`mysqladmin ping -h 127.0.0.1`**: cùng mẹo với `pg_isready -h 127.0.0.1` – trong lúc chạy `init.sql`, MySQL bật một server tạm **tắt mạng**,
  nên kiểm tra qua TCP chỉ đạt khi server thật đã lên.
- **`start_period: 30s`**: lần đầu MySQL mất ~20-30 giây để tạo file dữ liệu + chạy `init.sql`. Trong thời gian này healthcheck lỗi **không bị tính**
  (không làm container bị đánh dấu `unhealthy`).
- **Chuỗi JDBC** khác chuỗi `postgresql://user:pass@host/db` của Python/Go: user/mật khẩu là **biến riêng**, không nằm trong URL.

**MySQL khác PostgreSQL** (trong `init.sql`): tự tăng là `AUTO_INCREMENT` (Postgres: `GENERATED ALWAYS AS IDENTITY`);
`BOOLEAN` thực ra là `TINYINT(1)` (0/1); thời gian là `DATETIME(3)` (Postgres: `TIMESTAMPTZ`); cộng ngày `CURDATE() + INTERVAL 7 DAY`
(Postgres: `CURRENT_DATE + 7`); nên ghi `CHARACTER SET utf8mb4` để chứa đủ tiếng Việt và emoji.

## 5. Code (tham khảo, không cần cho build/deploy)

| File | Vai trò |
|---|---|
| `NotesApplication.java` | `main()` + `@SpringBootApplication`: quét package, tự cấu hình Tomcat, JSON, DB |
| `Note.java` | **Entity JPA**: một object = một dòng bảng `notes` (`@Entity`, `@Table`, `@Column`). Hibernate tự viết SQL |
| `NoteRepository.java` | Chỉ là **interface**: Spring Data tự viết code. `findAllByOrderByIdDesc` được sinh **từ chính tên hàm** |
| `NoteController.java` | `@RestController` + `@GetMapping`/`@PostMapping`…: các route của API.md |
| `ApiError.java`, `ApiExceptionHandler.java` | `@RestControllerAdvice`: mọi lỗi → `{"error": {"code", "message"}}` |

| | Go/Gin | Java/Spring |
|---|---|---|
| Route | `api.GET("/notes", fn)` | `@GetMapping("/notes")` trên một method |
| Truy cập DB | tự viết SQL (`pgx`) | **ORM** (JPA/Hibernate): làm việc với object, Hibernate sinh SQL |
| Tạo object dùng chung | tự tạo trong `main()` | **Dependency injection**: Spring tạo `NoteRepository` và truyền vào constructor của controller |
| Lỗi | trả `error` | `throw ApiError...` → `@ExceptionHandler` |

Như các app khác: không dùng `@RequestBody NoteInput` + `@Valid` (cách quen thuộc của Spring) mà tự đọc body,
để trả đúng `INVALID_JSON` / `VALIDATION_ERROR` của API.md.

## 6. Còn thiếu so với production (làm dần)

1. **Unit test** (`src/test/java`, JUnit) – Spring Boot hay test bằng `@SpringBootTest` + Testcontainers (MySQL thật trong Docker).
2. **Migration** (Flyway/Liquibase) thay cho `init.sql`: `init.sql` chỉ chạy lần đầu, còn đổi schema về sau (thêm cột…) cần công cụ ghi lại từng phiên bản.
3. **Healthcheck Spring Boot Actuator** (`/actuator/health`) cho Docker/monitoring.
4. **RAM**: MySQL + JVM ~700 MB – server đã nâng lên m7i-flex.large (8 GB) trước khi deploy. Vẫn nên đặt `mem_limit` (JVM tự co heap theo nhờ `MaxRAMPercentage`).
5. Khởi động chậm (~10 giây): deploy sẽ có vài giây 502 khi container backend mới chưa sẵn sàng. Giải pháp: healthcheck + chờ healthy trước khi chuyển traffic.
6. Frontend là bản chép của `apps/python/frontend`; chưa có `package-lock.json`.
