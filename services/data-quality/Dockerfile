FROM --platform=$BUILDPLATFORM python:3.12-slim AS builder
ARG TARGETARCH=arm64
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
# Install to /app/.venv — عشان الـ non-root user يقدر يوصله
RUN python -m venv /app/.venv && \
    /app/.venv/bin/pip install --no-cache-dir -r requirements.txt

# ── Runtime ───────────────────────────────────────────────────────────────
FROM python:3.12-slim
ARG BUILD_VERSION=dev

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# إنشاء non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Copy virtualenv من الـ builder
COPY --from=builder --chown=appuser:appuser /app/.venv /app/.venv
ENV PATH=/app/.venv/bin:$PATH

COPY --chown=appuser:appuser . .

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV VERSION=${BUILD_VERSION}

LABEL org.opencontainers.image.title="data-quality"
LABEL org.opencontainers.image.description="Data Quality service — Soda Core checks + contract validation"

USER appuser
EXPOSE 9101

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "9101", "--workers", "2"]
