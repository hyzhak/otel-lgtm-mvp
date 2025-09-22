FROM python:3.12-slim

WORKDIR /workspace

COPY tests/requirements-dev.txt /tmp/requirements-dev.txt
RUN pip install --no-cache-dir -r /tmp/requirements-dev.txt

CMD ["python", "-m", "pytest", "tests/integration", "-vv"]
