FROM alpine

RUN apk add --no-cache bash curl aws-cli postgresql-client && \
    curl -L https://fly.io/install.sh | sh

COPY ./pg-dump-to-s3.sh ./entrypoint.sh /

CMD [ "/entrypoint.sh" ]
