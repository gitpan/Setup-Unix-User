#!perl

use 5.010;
use strict;
use warnings;

use FindBin '$Bin';
use lib $Bin, "$Bin/t";

use Test::More 0.96;
require "testlib.pl";

use vars qw($undo_data $redo_data);

setup();

test_setup_unix_group(
    name       => "create (dry run)",
    args       => {name=>"g1", -dry_run=>1},
    status     => 200,
    exists     => 0,
);
test_setup_unix_group(
    name       => "create",
    args       => {name=>"g1"},
    status     => 200,
    posttest   => sub {
        my $res = shift;
        is($res->[2]{gid}, 3, "gid");
    },
);
test_setup_unix_group(
    name       => "create (with undo, min_new_gid)",
    args       => {name=>"g2", min_new_gid=>1000, -undo_action=>"do"},
    status     => 200,
    is_file    => 1,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok($undo_data, "there is undo data");
        is($res->[2]{gid}, 1001, "gid");
    },
);
test_setup_unix_group(
    name       => "create (undo, dry_run)",
    args       => {name=>"g2", -dry_run=>1,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
);
test_setup_unix_group(
    name       => "create (undo)",
    args       => {name=>"g2",
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    exists     => 0,
    posttest   => sub {
        my $res = shift;
        $redo_data = $res->[3]{undo_data};
    },
);
test_setup_unix_group(
    name       => "create (redo, dry_run)",
    args       => {name=>"g2", -dry_run=>1,
                   -undo_action=>"undo", -undo_data=>$redo_data},
    status     => 200,
    exists     => 0,
);
test_setup_unix_group(
    name       => "create (redo)",
    args       => {name=>"g2",
                   -undo_action=>"undo", -undo_data=>$redo_data},
    status     => 200,
    exists     => 1,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok($undo_data, "there is undo data");
    },
);

# XXX test: can't redo because gid is occupied

DONE_TESTING:
teardown();
