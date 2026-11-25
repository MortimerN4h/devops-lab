# ---- Stage 1 "build": Maven + full JDK (compiler) turn the source into ONE runnable jar ----
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
# pom.xml first: download all libraries in their own layer (cached until pom.xml changes)
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
# package = compile + run tests + build target/app.jar (-DskipTests: the API tests run in CI instead)
RUN mvn -B -q package -DskipTests

# ---- Stage 2: only a JRE (runs Java, cannot compile it) + the jar ----
FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S app && adduser -S -G app -u 10001 app
WORKDIR /app
COPY --from=build /src/target/app.jar app.jar
USER app
EXPOSE 8080
# MaxRAMPercentage: the JVM sizes its heap from the CONTAINER's memory limit (75% of it), not the host's
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]
