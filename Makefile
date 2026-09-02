.PHONY: validate helm-template yaml-check ansible-check ansible-check-container preflight-server

ENV ?=

validate: yaml-check helm-template ansible-check

yaml-check:
	./scripts/validate.sh yaml

helm-template:
	./scripts/validate.sh helm

ansible-check:
	./scripts/validate.sh ansible

ansible-check-container:
	./scripts/validate-ansible-container.sh

preflight-server:
	@test -n "$(ENV)" || (echo "usage: make preflight-server ENV=stg|prd" >&2; exit 2)
	./scripts/preflight-server-env.sh "$(ENV)"
