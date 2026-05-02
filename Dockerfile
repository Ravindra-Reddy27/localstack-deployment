# Stage 1: The Builder
# We use a heavier base image here because it contains build tools (like gcc) 
# that some Python packages need to compile.
FROM python:3.11-bullseye  AS builder

WORKDIR /app

# Create a virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy ONLY the requirements file first to leverage Docker layer caching
COPY ./requirements.txt .

# Install dependencies into the virtual environment without caching the pip downloads
RUN pip install --no-cache-dir -r requirements.txt


# Stage 2: The Runtime
# We switch to a highly minimal base image for the final product.
FROM python:3.11-slim-bullseye AS runtime

WORKDIR /app

# Copy the fully baked virtual environment from the builder stage
COPY --from=builder /opt/venv /opt/venv

# Copy our application source code
COPY ./main.py .

# Ensure the runtime uses the binaries from the virtual environment
ENV PATH="/opt/venv/bin:$PATH"

# Set the command to run our FastAPI app
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]