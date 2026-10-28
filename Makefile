.PHONY: pack push publish lint test clean check-set check-version

SET ?=
VERSION ?=
INPUT ?=
BATS ?= bats

pack: check-set
	scripts/pack.sh $(SET) "$(INPUT)"

push: check-set check-version
	scripts/push.sh $(SET) $(VERSION)

publish: pack push

lint:
	shellcheck -x scripts/*.sh test/*.sh test/*.bash test/fixtures/*.bash

test:
	$(BATS) test

clean:
	rm -rf build out

check-set:
	@test -n "$(SET)" || { echo "SET is required, e.g. make $(MAKECMDGOALS) SET=kds" >&2; exit 2; }

check-version:
	@test -n "$(VERSION)" || { echo "VERSION is required, e.g. make $(MAKECMDGOALS) SET=$(SET) VERSION=v1" >&2; exit 2; }
