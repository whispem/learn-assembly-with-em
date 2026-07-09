FROM --platform=linux/amd64 ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends nasm make binutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /asm
CMD ["bash"]
