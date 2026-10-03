.PHONY: check test

test:
	/bin/bash tests/run_all.sh

check:
	/bin/bash -n src/safe-rm
	/bin/bash tests/run_all.sh
