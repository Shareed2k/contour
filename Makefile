PROJECT = contour
REGISTRY ?= gcr.io/heptio-images
IMAGE := $(REGISTRY)/$(PROJECT)
SRCDIRS := ./cmd ./internal ./apis
PKGS := $(shell go list ./cmd/... ./pkg/...)
LOCAL_BOOTSTRAP_CONFIG = config.yaml
TAG_LATEST ?= false

GIT_REF = $(shell git rev-parse --short=8 --verify HEAD)
VERSION ?= $(GIT_REF)

export GO111MODULE=on

test: install
	go test ./...

test-race: | test
	go test -race ./...

vet: | test
	go vet ./...

check: test test-race vet gofmt misspell unconvert ineffassign
	@echo Checking rendered files are up to date
	@(cd deployment && bash render.sh && git diff --exit-code . || (echo "rendered files are out of date" && exit 1))

install:
	go install -v -tags "oidc gcp" ./...

download:
	go mod download

container:
	docker build . -t $(IMAGE):$(VERSION)

push: container
	docker push $(IMAGE):$(VERSION)
ifeq ($(TAG_LATEST), true)
	docker tag $(IMAGE):$(VERSION) $(IMAGE):latest
	docker push $(IMAGE):latest
endif

$(LOCAL_BOOTSTRAP_CONFIG): install
	contour bootstrap $@

local: $(LOCAL_BOOTSTRAP_CONFIG)
	docker run \
		-it \
		--mount type=bind,source=$(CURDIR),target=/config \
		-p 9001:9001 \
		-p 8002:8002 \
		docker.io/envoyproxy/envoy-alpine:v1.9.0 \
		envoy \
		--config-path /config/$< \
		--service-node node0 \
		--service-cluster cluster0

staticcheck:
	@go get honnef.co/go/tools/cmd/staticcheck
	staticcheck \
		-checks all,-ST1003 \
		$(PKGS)

misspell:
	@go get github.com/client9/misspell/cmd/misspell
	misspell \
		-i clas \
		-locale US \
		-error \
		cmd/* pkg/* docs/* design/* *.md

unconvert:
	@go get github.com/mdempsky/unconvert
	unconvert -v $(PKGS)

ineffassign:
	@go get github.com/gordonklaus/ineffassign
	find $(SRCDIRS) -name '*.go' | xargs ineffassign

pedantic: check unparam errcheck

unparam:
	@go get mvdan.cc/unparam
	unparam ./...

errcheck:
	@go get github.com/kisielk/errcheck
	errcheck $(PKGS)

render:
	@echo Rendering deployment files...
	@(cd deployment && bash render.sh)

updategenerated:
	@echo Updating CRD generated code...
	@(bash hack/update-generated-crd-code.sh)

gofmt:
	@echo Checking code is gofmted
	@test -z "$(shell gofmt -s -l -d -e $(SRCDIRS) | tee /dev/stderr)"
