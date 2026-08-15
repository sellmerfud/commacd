
all: lint test

lint:
	@type shellcheck >/dev/null 2>&1 || { echo "shellcheck (https://github.com/koalaman/shellcheck) wasn't found on the PATH. Please install it and try again."; exit 1; }
	shellcheck -s bash -f gcc commacd.sh

test:
	@type shpec >/dev/null 2>&1 || { echo "shpec (https://github.com/rylnd/shpec) wasn't found on the PATH. Please install it and try again"; exit 1; }
	bash -i -c "shpec"
