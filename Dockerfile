# https://hub.docker.com/_/alpine/tags
ARG ALPINE_IMAGE_TAG=3.23.3

FROM alpine:$ALPINE_IMAGE_TAG

RUN apk update && \
    apk add --no-cache \
        bash=5.3.3-r1 \
        curl=8.17.0-r1 \
        aws-cli=2.32.7-r0 \
        pigz=2.8-r1 \
        # Use the metapackage postgresql-client to find the appropriate postgresqlXX-client version
        postgresql17-client=17.9-r0 \
    && \
    curl -L https://fly.io/install.sh | sh

ENV PATH="/root/.fly/bin:$PATH"

COPY ./pg-dump-to-s3.sh ./entrypoint.sh /

CMD [ "/entrypoint.sh" ]
