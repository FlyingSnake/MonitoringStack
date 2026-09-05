.PHONY: validate helm-template yaml-check ansible-check ansible-check-container windows-contract-check preflight-server local-status local-ui-api-smoke local-k8s-alloy-smoke local-linux-alloy-smoke local-telemetry-smoke local-telemetry-clean

ENV ?=
OVERLAY ?=

validate: yaml-check helm-template ansible-check windows-contract-check

yaml-check:
	./scripts/validate.sh yaml

helm-template:
	./scripts/validate.sh helm

ansible-check:
	./scripts/validate.sh ansible

ansible-check-container:
	./scripts/validate-ansible-container.sh

windows-contract-check:
	./scripts/validate-windows-contract.sh

preflight-server:
	@test -n "$(ENV)" || (echo "usage: make preflight-server ENV=dev|stg|prd [OVERLAY=path/to/values.yaml]" >&2; exit 2)
	./scripts/preflight-server-env.sh "$(ENV)" "$(OVERLAY)"

local-status:
	./scripts/local/status.sh

local-ui-api-smoke: local-status
	./scripts/local/ui-api-smoke.sh

local-k8s-alloy-smoke: local-status
	./scripts/local/k8s-alloy-smoke.sh

local-linux-alloy-smoke: local-status
	./scripts/local/linux-alloy-smoke.sh

local-telemetry-smoke: local-status
	./tests/telemetry-workloads/build-images.sh
	./tests/telemetry-workloads/deploy.sh
	./tests/telemetry-workloads/verify.sh
	./tests/telemetry-workloads/query.sh

local-telemetry-clean:
	./tests/telemetry-workloads/destroy.sh
