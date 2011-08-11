#!perl

use 5.010;
use strict;
use warnings;

use FindBin '$Bin';
use lib $Bin, "$Bin/t";

use Test::More 0.96;
require "testlib.pl";

use vars qw($tmp_dir $undo_data $redo_data);

setup();

test_setup_unix_user(
    name       => "create (dry run)",
    args       => {name=>"u3", -dry_run=>1},
    status     => 200,
    exists     => 0,
);
test_setup_unix_user(
    name       => "create (with create_home_dir=0)",
    args       => {name=>"u3", create_home_dir=>0},
    status     => 200,
    posttest   => sub {
        my $res = shift;
        is($res->[2]{uid}, 3, "uid");
        is($res->[2]{gid}, 3, "gid");
    },
);
my %args = (
    name=>"u4", min_new_uid=>1000, new_password=>"123", new_gecos=>"user 4",
    new_home_dir=>"$tmp_dir/home", new_home_dir_mode=>0750,
    new_shell=>"/bin/shell", member_of=>["bin", "test"],
    skel_dir=>"$tmp_dir/skel",
);
test_setup_unix_user(
    name       => "create (with undo, min_new_uid, new_password, new_gecos, ".
        "new_home_dir, new_home_dir_mode, new_shell, member_of)",
    args       => {%args,
                   -undo_action=>"do"},
    status     => 200,
    posttest   => sub {
        my ($res, $name, $pu) = @_;
        $undo_data = $res->[3]{undo_data};
        is($res->[2]{uid}, 1002, "uid");
        is($res->[2]{gid}, 1003, "gid");
        my @u = $pu->user($name);
        # XXX test new_password
        is($u[3], "user 4", "new_gecos");
        is($u[4], "$tmp_dir/home", "new_home_dir");
        is($u[5], "/bin/shell", "new_shell");
        ok((-d "$tmp_dir/home"), "home dir created");
        ok((-f "$tmp_dir/home/.dir1/.file1"), "skel file/dir created 1a");
        is(read_file("$tmp_dir/home/.dir1/.file1", err_mode=>'quiet'), "file 1",
           "skel file/dir created 1b");
        ok((-f "$tmp_dir/home/.file2"), "skel file/dir created 2a");
        is(read_file("$tmp_dir/home/.file2", err_mode=>'quiet'), "file 2",
           "skel file/dir created 2b");
        my @g;
        @g = $pu->group("u4");
        ok($g[0] && "u4" !~~ @{$g[1]},
           "user is not member of u4 (private group not automatically added)")
            or diag explain $g[1];
        @g = $pu->group("bin");
        ok($g[0] && "u4" ~~ @{$g[1]}, "user is member of bin")
            or diag explain $g[1];
        ok($g[0] && "test" !~~ @{$g[1]},
           "user is not member of test (nonexistant group)")
            or diag explain $g[1];
    },
);
test_setup_unix_user(
    name       => "create (undo, dry_run)",
    args       => {%args, -dry_run=>1,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    posttest   => sub {
        my ($res, $name, $pu) = @_;
        my @u = $pu->user($name);
        ok($u[0], "user still exists");
        ok((-d "$tmp_dir/home"), "home dir still exists");
        ok((-f "$tmp_dir/home/.dir1/.file1"), "skel file still exists");
    },
);
test_setup_unix_user(
    name       => "create (undo)",
    args       => {%args,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    exists     => 0,
    posttest   => sub {
        my ($res, $name, $pu) = @_;
        $redo_data = $res->[3]{undo_data};
        my @u = $pu->user($name);
        ok(!(-e "$tmp_dir/home"), "home dir removed");
        #ok(!(-e "$tmp_dir/home/.dir1/.file1"), "skel file removed");#implied
        my @g = $pu->group($name);
        ok(!$g[0], "group removed");
    },
);
test_setup_unix_user(
    name       => "create (redo, dry_run)",
    args       => {%args, -dry_run=>1,
                   -undo_action=>"undo", -undo_data=>$redo_data},
    status     => 200,
    exists     => 0,
);
test_setup_unix_user(
    name       => "create (redo)",
    args       => {%args,
                   -undo_action=>"undo", -undo_data=>$redo_data},
    status     => 200,
    posttest   => sub {
        my ($res, $name, $pu) = @_;
        my @u = $pu->user($name);
        ok($u[0], "user recreated");
        is($u[1], 1002, "user recreated with same uid");
        my @g = $pu->group($name);
        is($g[0], 1003, "group recreated with same gid");
        ok((-d "$tmp_dir/home"), "home dir recreated");
        ok((-f "$tmp_dir/home/.dir1/.file1"), "skel file recreated");
    },
);

# at this point, users: u1=1000, u2=1001, u3=3, u4=1002

my %args2 = (
    name=>"u5", min_new_uid=>1000, max_new_uid=>1002,
    skel_dir=>"$tmp_dir/skel",
);
{
    local $args2{should_already_exist} = 1;
    test_setup_unix_user(
        name       => "create (should_already_exist, fail)",
        args       => {%args2},
        status     => 412,
        exists     => 0,
    );
}
test_setup_unix_user(
    name       => "create (min_new_uid, max_new_uid, fail getting unused uid)",
    args       => {%args2},
    status     => 500,
    exists     => 0,
);

{
    local $args{should_already_exist} = 1;
    test_setup_unix_user(
        name       => "create (should_already_exist, success)",
        args       => {%args},
        status     => 200, # should be 304, but we tried to add to group 'test'
    );
}

$args{member_of} = ["u2"];
$args{not_member_of} = ["bin"];

test_setup_unix_user(
    name       => "fix membership (with undo)",
    args       => {%args,
                   -undo_action=>"do"},
    status     => 200,
    posttest   => sub {
        my ($res, $name, $pu) = @_;
        $undo_data = $res->[3]{undo_data};
        my @g;
        @g = $pu->group("u4");
        ok($g[0] && "u4" ~~ @{$g[1]}, "user is member of u4")
            or diag explain $g[1];
        @g = $pu->group("u2");
        ok($g[0] && "u4" ~~ @{$g[1]}, "user is member of u2")
            or diag explain $g[1];
        @g = $pu->group("bin");
        ok($g[0] && !("u4" ~~ @{$g[1]}), "user is not member of bin")
            or diag explain $g[1];
    },
);
test_setup_unix_user(
    name       => "fix membership (with undo)",
    args       => {%args,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    posttest   => sub {
        my ($res, $name, $pu) = @_;
        $redo_data = $res->[3]{undo_data};
        my @g;
        @g = $pu->group("u4");
        ok($g[0] && "u4" ~~ @{$g[1]}, "user is member of u4")
            or diag explain $g[1];
        @g = $pu->group("u2");
        ok($g[0] && !("u4" ~~ @{$g[1]}), "user is not member of u2")
            or diag explain $g[1];
        @g = $pu->group("bin");
        ok($g[0] && "u4" ~~ @{$g[1]}, "user is member of bin")
            or diag explain $g[1];
    },
);

%args = (
    name=>"u5", new_home_dir=>"$tmp_dir/u5", member_of=>["bin"],
    skel_dir=>"$tmp_dir/skel",
);
test_setup_unix_user(
    name       => "changed state between do & undo: do",
    args       => {%args,
                   -undo_action=>"do"},
    status     => 200,
    posttest   => sub {
        my ($res, $name, $pu) = @_;
        $undo_data = $res->[3]{undo_data};
    },
);
write_file("$tmp_dir/u5/x", "test");   # file added to user's home
unlink "$tmp_dir/u5/.file2";           # file removed
write_file("$tmp_dir/u5/.file3", "x"); # file modified
test_setup_unix_user(
    name       => "changed state between do & undo: undo",
    args       => {%args,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    exists     => 0,
    posttest   => sub {
        my ($res, $name, $pu) = @_;
        $redo_data = $res->[3]{undo_data};
        ok((-d "$tmp_dir/u5"), "homedir not removed because not empty");
        ok((-f "$tmp_dir/u5/x"), "file added by us not removed");
        ok(!(-e "$tmp_dir/u5/.dir1"), "file added by do removed");
        ok((-f "$tmp_dir/u5/.file3"), "file modified by us not removed");
    },
);

# at this point, users: u1=1000, u2=1001, u3=3, u4=1002

test_setup_unix_user(
    name       => "create (primary_group not user)",
    args       => {name => 'nouser',
                   new_home_dir=>"$tmp_dir/home",
                   primary_group=>'nobody'},
    status     => 200,
    posttest   => sub {
        my ($res, $name, $pu) = @_;

        my @u = $pu->user($name);
        is($u[1], 4, "uid");

        my @g = $pu->group($name);
        ok(!$g[0], "group 'nouser' not created") or diag explain \@g;

        my @g = $pu->group('nobody');
        ok($g[0] && "nouser" ~~ @{$g[1]},
           "user is member of nobody (primary group)")
            or diag explain $g[1];
    },
);

test_setup_unix_user(
    name       => "create (primary_group always added ".
        "even if member_of doesn't include it)",
    args       => {name => 'nouser2',
                   new_home_dir=>"$tmp_dir/home",
                   primary_group=>'nobody',
                   member_of=>[]},
    status     => 200,
    posttest   => sub {
        my ($res, $name, $pu) = @_;

        my @u = $pu->user($name);
        is($u[1], 5, "uid");

        my @g = $pu->group($name);
        ok(!$g[0], "group 'nouser2' not created") or diag explain \@g;

        my @g = $pu->group('nobody');
        ok($g[0] && "nouser2" ~~ @{$g[1]},
           "user is member of nobody (primary group)")
            or diag explain $g[1];
    },
);

# at this point, users: u1=1000, u2=1001, u3=3, u4=1002, nouser=4, nouser2=5

# XXX test rollback

# XXX test failure during rollback (dies)

DONE_TESTING:
teardown();
