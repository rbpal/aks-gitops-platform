# One image, two roles: the API and the worker run the SAME image with a
# different command (set in their respective Deployments). Keeps the build and
# the supply chain simple — one image to scan, sign, and pin.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    HOME=/tmp

WORKDIR /app

# deps first → better layer caching on code-only changes
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY common.py app.py worker.py ./

# run as a non-root, unprivileged user (defence in depth; pairs with the
# pod securityContext: readOnlyRootFilesystem + drop ALL caps)
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
USER 10001

EXPOSE 8080

# Default = API. The worker Deployment overrides this with ["python","worker.py"].
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
