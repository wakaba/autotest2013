WGET = wget
PERL = perl
GIT = git
PERL_VERSION = 5.16.1
PERL_ENV = PATH="$(abspath local/perlbrew/perls/perl-$(PERL_VERSION)/bin):$(abspath local/perl-$(PERL_VERSION)/pm/bin):$(PATH)" PERL5LIB="$(shell cat config/perl/libs.txt)"
PROVE = `$(PERL_ENV) which prove`

all:

deps: git-submodules local-perl pmbp-install

git-submodules:
	$(GIT) submodule update --init

local/bin/pmbp.pl: always
	mkdir -p local/bin
	$(WGET) -O $@ https://github.com/wakaba/perl-setupenv/raw/master/bin/pmbp.pl

local-perl: local/bin/pmbp.pl
	$(PERL_ENV) $(PERL) local/bin/pmbp.pl --perl-version $(PERL_VERSION) --install-perl

pmbp-update: local/bin/pmbp.pl
	$(PERL_ENV) $(PERL) local/bin/pmbp.pl --update

pmbp-install: local/bin/pmbp.pl
	$(PERL_ENV) $(PERL) local/bin/pmbp.pl --install

test: test-deps test-main

test-deps: deps
	cd modules/rdb-utils && $(MAKE) deps

test-main:
	$(PERL_ENV) $(PROVE) t/action/*.t t/runner/*.t

PREPARE_DB_SET_PL = modules/rdb-utils/bin/prepare-db-set.pl
DB_SET_JSON = local/mysql/dsns.json

testdb-start:
	$(PERL_ENV) $(PERL) $(PREPARE_DB_SET_PL) --dsn-list $(DB_SET_JSON) \
	    --create-database autotestjobs

testdb-stop:
	$(PERL_ENV) $(PERL) $(PREPARE_DB_SET_PL) --dsn-list $(DB_SET_JSON) --stop

always:
