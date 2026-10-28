# ---- Stage 1: install dependencies (build tools never reach the final image) ----
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- Stage 2: minimal runtime image ----
FROM python:3.12-slim
ARG APP_VERSION=dev
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION}

# Dedicated non-root user with no login shell
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=builder /install /usr/local
COPY app/ ./app/

USER 10001
EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]