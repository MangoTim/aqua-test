# Use the official Python image as the base image
FROM python:3.12-slim-bookworm

# Set the working directory in the container
WORKDIR /app

# Copy the current directory contents into the container at /app
COPY . /app

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Install Flask and Werkzeug
RUN pip install Flask Werkzeug

# Install libcap2-bin so we can grant Python the ability to bind port 80 as non-root
RUN apt-get update && apt-get install -y --no-install-recommends libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user to run the app
RUN groupadd -r appuser \
    && useradd -r -g appuser -d /app -s /usr/sbin/nologin appuser \
    && chown -R appuser:appuser /app

# Grant appuser the ability to bind to privileged port 80
RUN setcap 'cap_net_bind_service=+ep' $(readlink -f $(which python))

# Make port 8083 available to the world outside this container
EXPOSE 8083

# Switch to non-root user
USER appuser

# Run app.py when the container launches
CMD ["python", "app.py"]
