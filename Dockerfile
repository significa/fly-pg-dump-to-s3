# https://hub.docker.com/_/alpine/tags
ARG IMAGE_TAG=3.21

FROM alpine:$IMAGE_TAG

RUN apk update && \
    apk add --no-cache bash curl aws-cli postgresql17-client=17.4-r0 pigz=2.8-r1 && \
    curl -L https://fly.io/install.sh | sh

ENV PATH="/root/.fly/bin:$PATH"

COPY ./pg-dump-to-s3.sh ./entrypoint.sh /

CMD [ "/entrypoint.sh" ]
