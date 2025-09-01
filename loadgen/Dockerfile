FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir httpx
COPY loadgen.py /app/loadgen.py
ENV TARGET_BASE_URL=http://app:8000
CMD ["python", "/app/loadgen.py"]
EXPOSE 8000
