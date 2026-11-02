FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY ccc_tools_server.py fs_tools.py ./
EXPOSE 8765
CMD ["python", "ccc_tools_server.py"]
