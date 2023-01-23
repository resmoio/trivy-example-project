## Build
FROM golang:1.19 AS build
WORKDIR /app
COPY go.mod ./
COPY go.sum ./
RUN go mod download
COPY *.go ./
RUN go build -o /kube-client

## Deploy
FROM gcr.io/distroless/base-debian9
WORKDIR /
COPY --from=build /kube-client /kube-client
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/kube-client"]