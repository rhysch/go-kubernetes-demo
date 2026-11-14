FROM golang:1.26-alpine AS build

WORKDIR /src
COPY go.mod main.go main_test.go ./

RUN go test ./...
RUN CGO_ENABLED=0 go build -o /go-web .

FROM scratch

COPY --from=build /go-web /go-web

USER 10001:10001
EXPOSE 8080

ENTRYPOINT ["/go-web"]
