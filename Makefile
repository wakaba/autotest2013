WGET = wget
PERL = ./perl
GIT = git
PROVE = ./prove

all:

## ------ Setup ------

deps: git-submodules pmbp-install

git-submodules:
	$(GIT) submodule update --init

local/bin/pmbp.pl:
	mkdir -p local/bin
	$(WGET) -O $@ https://github.com/wakaba/perl-setupenv/raw/master/bin/pmbp.pl

pmbp-upgrade: local/bin/pmbp.pl
	perl local/bin/pmbp.pl --update-pmbp-pl

pmbp-update: pmbp-upgrade
	perl local/bin/pmbp.pl --update

pmbp-install: pmbp-upgrade
	perl local/bin/pmbp.pl --install \
	    --create-perl-command-shortcut perl \
	    --create-perl-command-shortcut prove \
	    --add-to-gitignore /perl \
	    --add-to-gitignore /prove

## ------ Tests ------

test: test-deps test-main

test-deps: deps
	cd modules/rdb-utils && $(MAKE) deps

test-main:
	$(PROVE) t/action/*.t t/loader/*.t t/runner/*.t t/internal/*.t

PREPARE_DB_SET_PL = modules/rdb-utils/bin/prepare-db-set.pl
DB_SET_JSON = local/mysql/dsns.json

testdb-start:
	$(PERL) $(PREPARE_DB_SET_PL) --dsn-list $(DB_SET_JSON) \
	    --create-database autotestjobs

testdb-stop:
	$(PERL) $(PREPARE_DB_SET_PL) --dsn-list $(DB_SET_JSON) --stop

always:
