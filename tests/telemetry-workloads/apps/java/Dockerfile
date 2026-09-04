FROM maven:3.9.11-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml ./
COPY src ./src
RUN mvn -q -DskipTests package dependency:copy-dependencies -DincludeScope=runtime

FROM eclipse-temurin:21.0.8_9-jre
WORKDIR /app
RUN curl -fsSL -o /opt/pyroscope.jar https://github.com/grafana/pyroscope-java/releases/download/v2.9.1/pyroscope.jar
COPY --from=build /src/target/java-telemetry-0.1.0.jar ./app.jar
COPY --from=build /src/target/dependency ./dependency
EXPOSE 8080
CMD ["sh", "-c", "java -javaagent:/opt/pyroscope.jar -cp '/app/app.jar:/app/dependency/*' monitoring.stack.App"]
