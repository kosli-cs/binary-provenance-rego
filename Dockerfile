FROM golang:1.23 AS build
ARG VERSION=dev
WORKDIR /src
COPY app/ .
RUN CGO_ENABLED=0 go build -ldflags "-X main.version=${VERSION}" -o /hello-world .

FROM gcr.io/distroless/static:nonroot
COPY --from=build /hello-world /hello-world
EXPOSE 8080
ENTRYPOINT ["/hello-world"]
