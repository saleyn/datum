all: compile

compile test docs:
	mix $@

run:
	iex -S mix

clean:
	mix $@

publish:
	mix hex.publish$(if $(replace), --replace)

.PHONY: test
