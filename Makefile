.DEFAULT_GOAL := swvs

.PHONY: swvs
swvs:
	./_swift build -c release --target swvs

.PHONY: clean
clean:
	./_swift package clean
