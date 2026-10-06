# https://hub.docker.com/_/alpine/tags
ARG ALPINE_IMAGE_TAG=3.24.2

FROM alpine:$ALPINE_IMAGE_TAG

RUN apk update && \
    apk add --no-cache \
        bash=5.3.9-r1 \
        curl=8.22.0-r0 \
        aws-cli=2.34.63-r0 \
        pigz=2.8-r1 \
        # Use the metapackage postgresql-client to find the appropriate postgresqlXX-client version
        postgresql18-client=18.6-r0 \
    && \
    curl -L https://fly.io/install.sh | sh

ENV PATH="/root/.fly/bin:$PATH"

COPY ./pg-dump-to-s3.sh ./entrypoint.sh /

CMD [ "/entrypoint.sh" ]
