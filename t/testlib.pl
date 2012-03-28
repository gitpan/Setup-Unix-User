use 5.010;
use strict;
use warnings;

use File::chdir;
use File::Slurp;
use File::Temp qw(tempdir);
use Setup::Unix::Group qw(setup_unix_group);
use Setup::Unix::User  qw(setup_unix_user);
use Test::More 0.96;
use Test::Setup qw(test_setup);

my $passwd_path;
my $shadow_path;
my $group_path;
my $gshadow_path;

sub setup {
    plan skip_all => "No /etc/passwd, probably not Unix system"
        unless -f "/etc/passwd";

    $::tmp_dir = tempdir(CLEANUP => 1);
    $CWD = $::tmp_dir;

    $passwd_path = "$::tmp_dir/passwd";
    write_file($passwd_path, <<'_');
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/bin:/bin/sh
daemon:x:2:2:daemon:/sbin:/bin/sh
u1:x:1000:1000::/home/u1:/bin/bash
u2:x:1001:1001::/home/u2:/bin/bash
_

    $shadow_path = "$::tmp_dir/shadow";
    write_file($shadow_path, <<'_');
root:*:14607:0:99999:7:::
bin:*:14607:0:99999:7:::
daemon:*:14607:0:99999:7:::
u1:*:14607:0:99999:7:::
u2:*:14607:0:99999:7:::
_

    $group_path = "$::tmp_dir/group";
    write_file($group_path, <<'_');
root:x:0:
bin:x:1:
daemon:x:2:
nobody:x:111:
u1:x:1000:u1
u2:x:1002:u2
_

    $gshadow_path = "$::tmp_dir/gshadow";
    write_file($gshadow_path, <<'_');
root:::
bin:::
daemon:::
nobody:!::
u1:!::
u2:!::u1
_

    # setup skeleton
    mkdir("$::tmp_dir/skel");
    mkdir("$::tmp_dir/skel/.dir1");
    write_file("$::tmp_dir/skel/.dir1/.file1", "file 1");
    write_file("$::tmp_dir/skel/.file2", "file 2");
    write_file("$::tmp_dir/skel/.file3", "file 3");

    diag "tmp dir = $::tmp_dir";
}

sub teardown {
    done_testing();
    if (Test::More->builder->is_passing) {
        #diag "all tests successful, deleting temp files";
        $CWD = "/";
    } else {
        diag "there are failing tests, not deleting temp files";
    }
}

sub _test_setup_unix_group_or_file {
    my ($which, %tsuargs) = @_;

    my %tsargs;
    for (qw/check_state1 check_state2
            name dry_do_error do_error set_state1 set_state2 prepare cleanup/) {
        $tsargs{$_} = $tsuargs{$_};
    }
    $tsargs{function} = $which eq 'group' ?
        \&setup_unix_group : \&setup_unix_user;
    my %fargs = %{ $tsuargs{args} };
    $fargs{_passwd_path}  = $passwd_path;
    $fargs{_group_path}   = $group_path;
    $fargs{_shadow_path}  = $shadow_path;
    $fargs{_gshadow_path} = $gshadow_path;
    $tsargs{args} = \%fargs;

    my $name = $fargs{name};
    my $check = sub {
        my %cargs = @_;

        $::pu = Passwd::Unix::Alt->new(
            passwd  => $passwd_path,
            group   => $group_path,
            shadow  => $shadow_path,
            gshadow => $gshadow_path,
        );
        my @e;
        if ($which eq 'user') {
            @e = $::pu->user($name);
        } else {
            @e = $::pu->group($name);
        }
        #diag explain \@e;

        my $exists = $e[0] ? 1:0;

        if ($cargs{exists} // 1) {
            ok($exists, "exists") or return;
            if ($which eq 'user') {
                if (defined $cargs{uid}) {
                    is($e[1], $cargs{uid}, "uid");
                }
                if (defined $cargs{gid}) {
                    is($e[2], $cargs{gid}, "gid");
                }
            } else {
                if (defined $cargs{gid}) {
                    is($e[0], $cargs{gid}, "gid");
                }
            }
        } else {
            ok(!$exists, "does not exist");
        }

        if ($which eq 'user') {
            if ($cargs{member_of}) {
                my @g;
                for my $g (@{ $cargs{member_of} }) {
                    @g = $::pu->group($g);
                    ok($g[0] && $name ~~ @{$g[1]}, "user $name is member of $g")
                        or diag "members of group $g: " . join(" ", @{$g[1]});
                }
            }
            if ($cargs{not_member_of}) {
                my @g;
                for my $g (@{ $cargs{not_member_of} }) {
                    @g = $::pu->group($g);
                    ok(!$g[0] || !($name ~~ @{$g[1]}),
                       "user $name is not member of $g")
                        or diag "members of group $g: " . join(" ", @{$g[1]});
                }
            }
        }

        if ($cargs{extra}) {
            $cargs{extra}->();
        }
    };

    $tsargs{check_setup}   = sub { $check->(%{$tsuargs{check_setup}}) };
    $tsargs{check_unsetup} = sub { $check->(%{$tsuargs{check_unsetup}}) };

    test_setup(%tsargs);
}

sub test_setup_unix_group { _test_setup_unix_group_or_file('group', @_) }

sub test_setup_unix_user  { _test_setup_unix_group_or_file('user',  @_) }

1;
