#!perl

use 5.010;
use strict;
use warnings;

use FindBin '$Bin';
use lib $Bin, "$Bin/t";

use Test::More 0.96;
require "testlib.pl";

setup();

test_setup_unix_group(
    name          => "create",
    args          => {name=>"g1"},
    check_unsetup => {exists=>0},
    check_setup   => {gid=>3},
);
test_setup_unix_group(
    name          => "create with min_new_gid & max_new_gid",
    args          => {name=>"g2", min_new_gid=>1000, max_new_gid=>1002},
    check_unsetup => {exists=>0},
    check_setup   => {gid=>1001},
);
test_setup_unix_group(
    name          => "create failed due gids 1000, 1001, 1002 unavailable",
    args          => {name=>"g3", min_new_gid=>1000, max_new_gid=>1002},
    check_unsetup => {exists=>0},
    do_error      => 500,
);
test_setup_unix_group(
    name          => "create with min_new_gid & max_new_gid (2)",
    args          => {name=>"g3", min_new_gid=>1000, max_new_gid=>1003},
    check_unsetup => {exists=>0},
    check_setup   => {gid=>1003},
);
test_setup_unix_group(
    name          => "create already created -> noop",
    args          => {name=>"g2", min_new_gid=>1002, max_new_gid=>1002},
    check_unsetup => {gid=>1001},
    check_setup   => {gid=>1001},
);
goto DONE_TESTING;

DONE_TESTING:
teardown();
