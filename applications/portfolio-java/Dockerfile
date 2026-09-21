# syntax=docker/dockerfile:1.7

# ============================================================
# STAGE 1 - BUILD
# Maven + JDK servent uniquement à construire le JAR
# ============================================================

FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /workspace

# On copie d'abord uniquement le pom.xml.
# Cela permet à Docker de mettre les dépendances Maven en cache.
COPY pom.xml .

RUN --mount=type=cache,target=/root/.m2 \
    mvn -B dependency:go-offline

# Ensuite seulement on copie le code source.
COPY src ./src

# Construction de l'application.
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -DskipTests clean package && \
    JAR_FILE="$(find target -maxdepth 1 -type f -name '*.jar' ! -name '*.original' | head -n 1)" && \
    cp "${JAR_FILE}" /workspace/app.jar


# ============================================================
# STAGE 2 - RUNTIME
# L'image finale contient seulement Java Runtime + notre JAR
# ============================================================

FROM eclipse-temurin:21-jre-jammy AS runtime

WORKDIR /app

# Utilisateur non-root
RUN groupadd --gid 10001 appgroup && \
    useradd \
      --uid 10001 \
      --gid 10001 \
      --no-create-home \
      --shell /usr/sbin/nologin \
      appuser

COPY --from=build --chown=10001:10001 /workspace/app.jar /app/app.jar

# HOME dans /tmp pour rester compatible avec des environnements
# containerisés où l'utilisateur n'a pas de vrai home directory.
ENV HOME=/tmp

# Options JVM adaptées à un container.
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"

USER 10001

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]