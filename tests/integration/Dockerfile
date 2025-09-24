FROM python:3.12-slim

WORKDIR /workspace

COPY tests/requirements-dev.txt /tmp/requirements-dev.txt
RUN pip install --no-cache-dir -r /tmp/requirements-dev.txt

# Bundle the integration test suite so the image can run standalone inside Kubernetes clusters
COPY pytest.ini ./
COPY tests/__init__.py ./tests/__init__.py
COPY tests/integration ./tests/integration

CMD ["python", "-m", "pytest", "tests/integration", "-vv"]
