# Parametrized, reproducible per-framework proof image.
# Build:  docker build -f tests/frameworks/Dockerfile \
#            --build-arg FRAMEWORK=<fw> --build-arg VERSION="<pip spec>" -t hb-fw-<fw> <repo-root>
# One recipe builds any framework's image from a pinned matrix entry (tests/frameworks/matrix.txt).
FROM python:3.11-slim

ARG FRAMEWORK
ARG VERSION

WORKDIR /hb
# Install HeartBeat (stdlib-only core) from the mounted repo, then the pinned framework.
COPY py /hb/py
RUN pip install --no-cache-dir ./py \
 && pip install --no-cache-dir ${VERSION}

COPY tests/frameworks/incontainer.sh /hb/incontainer.sh
ENV HB_EXEC_BACKEND=${FRAMEWORK} \
    HB_EXEC_PROVIDER=ollama \
    HB_NO_GIT=1 STUCK_TICKS=999 HB_ROT_CHECK=0
ENTRYPOINT ["bash", "/hb/incontainer.sh"]
