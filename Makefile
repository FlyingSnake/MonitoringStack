.PHONY: validate helm-template yaml-check ansible-check

validate: yaml-check helm-template ansible-check

yaml-check:
	./scripts/validate.sh yaml

helm-template:
	./scripts/validate.sh helm

ansible-check:
	./scripts/validate.sh ansible
