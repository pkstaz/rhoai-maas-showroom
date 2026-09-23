FROM registry.access.redhat.com/ubi9/python-312:latest
WORKDIR /opt/app
COPY agent.py /opt/app/agent.py
EXPOSE 8080
ENV PORT=8080 HOST=0.0.0.0
USER 1001
CMD ["python3", "/opt/app/agent.py"]
