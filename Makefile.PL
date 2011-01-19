use inc::Module::Install;
name 'WebService-AppStoreAPI';
all_from 'lib/WebService/AppStoreAPI.pm';

# requires '';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
auto_set_repository;
auto_include;
WriteAll;
