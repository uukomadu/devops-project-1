# Docker-only targets: nothing here needs checkov or python installed.
# terraform itself runs from the pinned image too, so `make all` on a laptop
# and the CI job run the same versions.
SHELL := /usr/bin/env bash
TF_IMAGE := hashicorp/terraform:1.15

.PHONY: help scan scan-full fmt validate all

help:
	@echo "make scan       gated checkov scan of terraform/, fails on any check in checks.txt"
	@echo "make scan-full  every checkov finding, gates on nothing"
	@echo "make fmt        terraform fmt -check"
	@echo "make validate   terraform init -backend=false && terraform validate"
	@echo "make all        fmt + validate + scan"

scan:
	@./scan.sh

scan-full:
	@./scan.sh --full

fmt:
	@docker run --rm -v "$(CURDIR)/terraform:/w" -w /w --entrypoint terraform $(TF_IMAGE) \
		fmt -check -recursive -no-color

validate:
	@docker run --rm -v "$(CURDIR)/terraform:/w" -w /w --entrypoint sh $(TF_IMAGE) \
		-c 'terraform init -backend=false -input=false -no-color >/dev/null && terraform validate -no-color'

all: fmt validate scan
