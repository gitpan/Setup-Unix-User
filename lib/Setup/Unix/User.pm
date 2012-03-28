package Setup::Unix::User;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use File::chdir;
use File::Find;
use File::Slurp;
use Setup::Unix::Group qw(setup_unix_group);
use Setup::File        qw(setup_file);
use Setup::File::Dir   qw(setup_dir);
use Text::Password::Pronounceable;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_unix_user);

our $VERSION = '0.09'; # VERSION

our %SPEC;

sub _get_user_membership {
    my ($name, $pu) = @_;
    my @res;
    for ($pu->groups) {
        my @g = $pu->group($_);
        push @res, $_ if $name ~~ @{$g[1]};
    }
    @res;
}

sub _rand_pass {
    Text::Password::Pronounceable->generate(10, 16);
}

$SPEC{setup_unix_user} = {
    summary  => "Setup Unix user (existence, group memberships)",
    description => <<'_',

On do, will create Unix user if not already exists. And also make sure user
belong to specified groups (and not belong to unwanted groups). Return the
created UID/GID in the result.

On undo, will delete Unix user (along with its initially created home dir and
files) if it was created by this function. Also will restore old group
memberships.

_
    args => {
        name => ['str*' => {
            summary => 'User name',
        }],
        should_already_exist => ['bool' => {
            summary => 'If set to true, require that user already exists',
            description => <<'_',

This can be used to fix user membership, but does not create user when it
doesn't exist.

_
            default => 0,
        }],
        member_of => ['array' => {
            summary => 'List of Unix group names that the user must be '.
                'member of',
            description => <<'_',

If not specified, member_of will be set to just the primary group. The primary
group will always be added even if not specified.

_
            of => 'str*',
        }],
        not_member_of => ['str*' => {
            summary => 'List of Unix group names that the user must NOT be '.
                'member of',
            of => 'str*',
        }],
        min_new_uid => ['str' => {
            summary => 'Set minimum UID when creating new user',
            default => 0,
        }],
        max_new_uid => ['str' => {
            summary => 'Set maximum UID when creating new user',
            default => 65534,
        }],
        min_new_gid => ['str' => {
            summary => 'Set minimum GID when creating new group',
            description => 'Default is UID',
        }],
        max_new_gid => ['str' => {
            summary => 'Set maximum GID when creating new group',
            description => 'Default follows max_new_uid',
        }],
        new_password => ['str' => {
            summary => 'Set password when creating new user',
            description => 'Default is a random password',
        }],
        new_gecos => ['str' => {
            summary => 'Set gecos (usually, full name) when creating new user',
            default => '',
        }],
        new_home_dir => ['str' => {
            summary => 'Set home directory when creating new user, '.
                'defaults to /home/<username>',
        }],
        new_home_dir_mode => [int => {
            summary => 'Set permission mode of home dir '.
                'when creating new user',
            default => 0700,
        }],
        new_shell => ['str' => {
            summary => 'Set shell when creating new user',
            default => '/bin/bash',
        }],
        skel_dir => [str => {
            summary => 'Directory to get skeleton files when creating new user',
            default => '/etc/skel',
        }],
        create_home_dir => [bool => {
            summary => 'Whether to create homedir when creating new user',
            default => 1,
        }],
        use_skel_dir => [bool => {
            summary => 'Whether to copy files from skeleton dir '.
                'when creating new user',
            default => 1,
        }],
        primary_group => ['str' => {
            summary => "Specify user's primary group",
            description => <<'_',

In Unix systems, a user must be a member of at least one group. This group is
referred to as the primary group. By default, primary group name is the same as
the user name. The group will be created if not exists.

_
        }],
    },
    features => {undo=>1, dry_run=>1},
};
sub setup_unix_user {
    my %args           = @_;
    my $dry_run        = $args{-dry_run};
    my $undo_action    = $args{-undo_action} // "";

    # check args
    my $name           = $args{name};
    $name or return [400, "Please specify name"];
    $name =~ /^[A-Za-z0-9_-]+$/ or return [400, "Invalid group name syntax"];
    my $new_password      = $args{new_password}      // _rand_pass();
    my $new_gecos         = $args{new_gecos}         // "";
    my $new_home_dir      = $args{new_home_dir}      // "/home/$name";
    my $new_home_dir_mode = $args{new_home_dir_mode} // 0700;
    my $new_shell         = $args{new_shell}         // "/bin/bash";
    my $create_home_dir   = $args{create_home_dir}   // 1;
    my $use_skel_dir      = $args{use_skel_dir}      // 1;
    my $skel_dir          = $args{skel_dir}          // "/etc/skel";
    my $primary_group     = $args{primary_group}     // $name;
    my $member_of         = $args{member_of}         // [];
    push @$member_of, $primary_group unless $primary_group ~~ @$member_of;
    my $not_member_of     = $args{not_member_of}     // [];
    for (@$member_of) {
        return [400, "Group $_ is in member_of and not_member_of"]
            if $_ ~~ @$not_member_of;
    }

    # create PUA object
    my $passwd_path  = $args{_passwd_path}  // "/etc/passwd";
    my $group_path   = $args{_group_path}   // "/etc/group";
    my $shadow_path  = $args{_shadow_path}  // "/etc/shadow";
    my $gshadow_path = $args{_gshadow_path} // "/etc/gshadow";
    my $pu = Passwd::Unix::Alt->new(
        passwd   => $passwd_path,
        group    => $group_path,
        shadow   => $shadow_path,
        gshadow  => $gshadow_path,
        warnings => 0,
        #lock     => 1,
    );

    my ($uid, $gid);

    # check current state and collect steps
    my $steps;
    if ($undo_action eq 'undo') {
        $steps = $args{-undo_data} or return [400, "Please supply -undo_data"];
    } else {
        $steps = [];
        {
            my @u = $pu->user($name);
            if (!@u) {
                $log->infof("nok: unix user $name doesn't exist");
                return [412, "user must already exist"]
                    if $args{should_already_exist};
                push @$steps, ["create", "fix_membership", ""];
                last;
            }

            $uid = $u[1];
            $gid = $u[2];
            my @membership = _get_user_membership($name, $pu);
            for (@$member_of) {
                my @g = $pu->group($_);
                if (!$g[0]) {
                    $log->info("unix user $name should be member of $_ ".
                                   "but the group doesn't exist, ignored");
                    next;
                }
                unless ($_ ~~ @membership) {
                    $log->info("nok: unix user $name should be ".
                                   "member of $_ but isn't");
                    push @$steps, ["add_group", $_];
                }
            }
            for (@$not_member_of) {
                if ($_ ~~ @membership) {
                    $log->info("nok: unix user $name should NOT be ".
                                   "member of $_ but is");
                    push @$steps, ["remove_group", $_];
                }
            }
        }
    }

    return [400, "Invalid steps, must be an array"]
        unless $steps && ref($steps) eq 'ARRAY';
    return [200, "Dry run"] if $dry_run && @$steps;

    my $save_undo = $undo_action ? 1:0;
    my $undo_hint = $args{-undo_hint} // {};
    return [400, "Invalid -undo_hint, please supply a hashref"]
        unless ref($undo_hint) eq 'HASH';
    my $tmp_dir = $undo_hint->{tmp_dir};

    # perform the steps
    my $rollback;
    my $undo_steps = [];
  STEP:
    for my $i (0..@$steps-1) {
        my $step = $steps->[$i];
        next unless defined $step; # can happen even when steps=[], due to redo
        $log->tracef("step %d of 0..%d: %s", $i, @$steps-1, $step);
        my $err;
        return [400, "Invalid step (not array)"] unless ref($step) eq 'ARRAY';

        if ($step->[0] eq 'create') { # arg: [uid, gid, [encp, gecos, home, sh]]

            $uid = undef; $gid = undef;
            my @u = $pu->user($name);
            if (@u) {
                if (defined($step->[1])) {
                    if ($step->[1] ne $u[1]) {
                        $err = "User already exists, but with different ".
                            "UID $u[1] (we need to create UID $step->[1])";
                        goto CHECK_ERR;
                    }
                    $uid = $u[1];
                }
                if (defined($step->[2])) {
                    if ($step->[2] ne $u[2]) {
                        $err = "User already exists, but with different ".
                            "GID $u[2] (we need to create GID $step->[2])";
                        goto CHECK_ERR;
                    }
                    $gid = $u[2];
                }
                # user already exists with correct uid/gid, skip this step
                next STEP;
            }
            my $found = defined($uid);
            my $minuid = $args{min_new_uid} // 1;
            my $maxuid = $args{max_new_uid} // 65535;
            if (!$found) {
                $log->trace("finding an unused UID ...");
                my @uids = map {($pu->user($_))[1]} $pu->users;
                $uid = $minuid;
                while (1) {
                    last if $uid > $maxuid;
                    unless ($uid ~~ @uids) {
                        $log->tracef("found unused UID: %d", $uid);
                        $found++;
                        last;
                    }
                    $uid++;
                }
            }
            if (!$found) {
                $err = "Can't find unused UID";
                goto CHECK_ERR;
            }
            $found = defined($gid);
            my $mingid = $args{min_new_gid} // $uid;
            my $maxgid = $args{max_new_gid} // $maxuid;
            my $pgroup = $primary_group     // $name;
            if (!$found) {
                my @g = $pu->group($pgroup);
                if ($g[0]) {
                    $gid = $g[0];
                } else {
                    $log->trace("Creating primary group for user $name: ".
                                    "$pgroup ...");
                    my %s_args = (
                        name          => $pgroup,
                        _passwd_path  => $passwd_path,
                        _shadow_path  => $shadow_path,
                        _group_path   => $group_path,
                        _gshadow_path => $gshadow_path,
                        min_new_gid   => $mingid,
                        max_new_gid   => $maxgid,
                    );
                    my $res = setup_unix_group(
                        %s_args, -undo_action => $save_undo ? 'do' : undef);
                    $log->tracef("res from setup_unix_group: %s", $res);
                    if ($res->[0] != 200) {
                        $err = "Can't setup Unix group $pgroup: ".
                            "$res->[0] - $res->[1]";
                    } else {
                        $gid = $res->[2]{gid};
                        unshift @$undo_steps,
                            ["unsetup_unix_group", \%s_args,
                             $res->[3]{undo_data}];
                    }
                }
            }

            $log->trace("Creating Unix user $name ...");
            if (defined $step->[3]) {
                $pu->user($name, $step->[3], $step->[1], $step->[2],
                          $step->[4], $step->[5], $step->[6]);
            } else {
                $pu->user($name, $pu->encpass($new_password), $uid, $gid,
                          $new_gecos, $new_home_dir, $new_shell);
            }
            if ($Passwd::Unix::Alt::errstr) {
                $err = "Can't add Unix passwd entry: ".
                    $Passwd::Unix::Alt::errstr;
            } else {
                unshift @$undo_steps, ["delete"];
            }

            for my $gi (@$member_of) {
                my @g = $pu->group($gi); # XXX check error
                unless ($g[0]) {
                    $log->warn("group $gi doesn't exist, skipped");
                    next;
                }
                unless ($name ~~ @{$g[1]}) {
                    $log->trace("Adding user $name to group $gi ...");
                    push @{$g[1]}, $name;
                    $pu->group($gi, $g[0], $g[1]);
                    if ($Passwd::Unix::Alt::errstr) {
                        $err = "Can't add user to group $gi: ".
                            $Passwd::Unix::Alt::errstr;
                        goto CHECK_ERR;
                    }
                }
            }

            if ($create_home_dir) {
                $log->tracef("Creating home dir %s ...", $new_home_dir);
                my %s_args = (path=>$new_home_dir, mode=>$new_home_dir_mode,
                              should_exist=>1);
                unless ($>) {
                    $s_args{owner} = $uid;
                    $s_args{group} = $gid;
                }
                my $res = setup_dir(%s_args, -undo_action=>"do",
                                    -undo_hint=>{tmp_dir=>$tmp_dir});
                if ($res->[0] != 200 && $res->[0] != 304) {
                    $err = "Can't create home dir: $res->[0] - $res->[1]";
                    goto CHECK_ERR;
                }
                unshift @$undo_steps,
                    ["unsetup_dir", \%s_args, $res->[3]{undo_data}]
                        unless $res->[0] == 304;
            }
            if ($create_home_dir && $use_skel_dir) {
                my $old_cwd = $CWD;
                if (!(-d $skel_dir)) {
                    $log->warnf("skel dir %s doesn't exist, ".
                                    "skipped copying files", $skel_dir);
                } elsif (!(eval { $CWD = $skel_dir })) {
                    $log->warnf("Can't chdir to skel dir %s, skipped");
                } else {
                    $log->tracef("Copying files from skeleton %s ...",
                                 $skel_dir);
                    # XXX currently all file/dir created default mode (755/644)
                    # XXX doesn't handle symlink yet
                    find(
                        sub {
                            return if $_ eq '.' || $_ eq '..';
                            my $d = $File::Find::dir;
                            $d =~ s!^\./?!!;
                            my $p = (length($d) ? "$d/" : "").$_;
                            $log->tracef("skel: %s", $p); # TMP
                            my %s_args = (path=>"$new_home_dir/$p",
                                          should_exist=>1);
                            my $res;
                            if (-d $_) {
                                $res = setup_dir(
                                    %s_args, -undo_action=>"do",
                                    -undo_hint=>{tmp_dir=>$tmp_dir});
                                # ignore error
                                if ($res->[0] == 200) {
                                    unshift @$undo_steps,
                                        ["unsetup_dir",
                                         \%s_args, $res->[3]{undo_data}];
                                }
                            } else {
                                my $content = read_file($_, err_mode=>'quiet');
                                $res = setup_file(
                                    %s_args, -undo_action=>"do",
                                    gen_content_code=>sub {$content},
                                    -undo_hint=>{tmp_dir=>$tmp_dir});
                                # ignore error
                                if ($res->[0] == 200) {
                                    unshift @$undo_steps,
                                        ["unsetup_file",
                                         \%s_args, $res->[3]{undo_data},
                                         $content];
                                }
                            }
                        }, "."
                    );
                    $CWD = $old_cwd;
                } # if copy skel
            } # if create home dir

        } elsif ($step->[0] eq 'delete') { # arg: -

            $pu->del($name);
            if ($Passwd::Unix::Alt::errstr) {
                $err = $Passwd::Unix::Alt::errstr;
            } else {
                unshift @$undo_steps, ['create', @{$step}[1..@$step-1]];
            }

        } elsif ($step->[0] eq 'add_group') { # arg: group name

            my $gi = $step->[1];
            my @g = $pu->group($gi); # XXX check error
            unless ($g[0]) {
                $log->warn("group $gi doesn't exist, skipped");
                next STEP;
            }
            if ($name ~~ @{$g[1]}) {
                # user already member of this group
                next STEP;
            }
            $log->trace("Adding $name to group $gi ...");
            push @{$g[1]}, $name;
            $pu->group($gi, $g[0], $g[1]);
            if ($Passwd::Unix::Alt::errstr) {
                $err = "Can't add user to group $gi: ".
                    $Passwd::Unix::Alt::errstr;
                goto CHECK_ERR;
            }
            unshift @$undo_steps, ["remove_group", $gi];

        } elsif ($step->[0] eq 'remove_group') { # arg: group name

            my $gi = $step->[1];
            my @g = $pu->group($gi); # XXX check error
            unless ($g[0]) {
                $log->warn("group $gi doesn't exist, skipped");
                next STEP;
            }
            unless ($name ~~ @{$g[1]}) {
                # user already not member of this group
                next STEP;
            }
            $log->trace("Removing $name from group $i ...");
            $g[1] = [grep {$_ ne $name} @{$g[1]}];
            $pu->group($gi, $g[0], $g[1]);
            if ($Passwd::Unix::Alt::errstr) {
                $err = "Can't add user to group $gi: ".
                    $Passwd::Unix::Alt::errstr;
                goto CHECK_ERR;
            }
            unshift @$undo_steps, ["add_group", $gi];

        } elsif ($step->[0] =~ /^(un)?(setup_(?:dir|file|unix_group))$/) {

            my ($is_undo, $f) = ($1, $2);
            my %s_args = %{$step->[1]};
            my %a_args = ();
            if ($f eq 'setup_file') {
                # can't serialize coderef, so we carry around content
                $a_args{gen_content_code} = sub { $step->[3] };
            }
            $a_args{-undo_action} = $is_undo ? "undo" : "do";
            $a_args{-undo_data}   = $step->[2];
            $a_args{-undo_hint}   = {tmp_dir=>$tmp_dir};
            no strict 'refs';
            my $res = $f->(%s_args, %a_args);
            if ($res->[0] == 200) {
                unshift @$undo_steps, [
                    ($is_undo ? "" : "un").$f,
                    \%s_args,
                    $res->[3]{undo_data},
                    $f eq 'setup_file' ? $step->[3] : undef,
                ];
            } elsif ($res->[0] == 304) {
                # nothing was done, success, no undo
            } else {
                # ignore setup_dir errors
                if ($f eq 'setup_dir') {
                    $log->warn("Can't successfully run $step->[0]: ".
                                   "$res->[0] - $res->[1], ignored");
                } else {
                    $err = "Error result from $f: $res->[0] - $res->[1]";
                }
            }

        } else {

            die "BUG: Unknown step command: $step->[0]";

        }
      CHECK_ERR:
        if ($err) {
            if ($rollback) {
                die "Failed rollback step $i of 0..".(@$steps-1).": $err";
            } else {
                $log->tracef("Step failed: $err, performing rollback (%s)...",
                             $undo_steps);
                $rollback = $err;
                $steps = $undo_steps;
                goto STEP; # perform steps all over again
            }
        }
    }
    return [500, "Error (rollbacked): $rollback"] if $rollback;

    my $data = {uid=>$uid, gid=>$gid};
    my $meta = {};
    $meta->{undo_data} = $undo_steps if $save_undo;
    $log->tracef("meta: %s", $meta);
    return [@$steps ? 200 : 304, @$steps ? "OK" : "Nothing done", $data, $meta];
}

1;
# ABSTRACT: Setup Unix user (existence, home dir, group memberships)


=pod

=head1 NAME

Setup::Unix::User - Setup Unix user (existence, home dir, group memberships)

=head1 VERSION

version 0.09

=head1 SYNOPSIS

 use Setup::Unix::User 'setup_unix_user';

 # simple usage (doesn't save undo data)
 my $res = setup_unix_user name => 'foo',
                           member_of => ['admin', 'wheel'];
 die unless $res->[0] == 200 || $res->[0] == 304;

 # perform setup and save undo data (undo data should be serializable)
 $res = setup_unix_user ..., -undo_action => 'do';
 die unless $res->[0] == 200 || $res->[0] == 304;
 my $undo_data = $res->[3]{undo_data};

 # perform undo
 $res = setup_unix_user ..., -undo_action => "undo", -undo_data=>$undo_data;
 die unless $res->[0] == 200 || $res->[0] == 304;

=head1 DESCRIPTION

This module provides one function: B<setup_unix_user>.

This module is part of the Setup modules family.

This module uses L<Log::Any> logging framework.

This module has L<Rinci> metadata.

=head1 THE SETUP MODULES FAMILY

I use the C<Setup::> namespace for the Setup modules family. See L<Setup::File>
for more details on the goals, characteristics, and implementation of Setup
modules family.

=head1 FUNCTIONS

None are exported by default, but they are exportable.

=head1 FAQ

=head2 How to create user with a specific UID and/or GID?

Set C<min_new_uid> and C<max_new_uid> (and/or C<min_new_gid> and C<max_new_gid>)
to your desired values. Note that the function will report failure if when
wanting to create a user, the desired UID is already taken. But the function
will not report failure if the user already exists, even with a different UID.

=head2 How to create user without creating a group with the same name as that user?

By default, C<primary_group> is set to the same name as the user. You can set it
to an existing group, e.g. "users" and the setup function will not create a new
group with the same name as user.

=head1 SEE ALSO

L<Setup::Unix::Group>.

Other modules in Setup:: namespace.

=head1 FUNCTIONS


=head2 setup_unix_user(%args) -> [status, msg, result, meta]

Setup Unix user (existence, group memberships).

On do, will create Unix user if not already exists. And also make sure user
belong to specified groups (and not belong to unwanted groups). Return the
created UID/GID in the result.

On undo, will delete Unix user (along with its initially created home dir and
files) if it was created by this function. Also will restore old group
memberships.

Arguments ('*' denotes required arguments):

=over 4

=item * B<create_home_dir> => I<bool> (default: 1)

Whether to create homedir when creating new user.

=item * B<max_new_gid> => I<str>

Set maximum GID when creating new group.

Default follows maxB<new>uid

=item * B<max_new_uid> => I<str> (default: 65534)

Set maximum UID when creating new user.

=item * B<member_of> => I<array>

List of Unix group names that the user must be member of.

If not specified, member_of will be set to just the primary group. The primary
group will always be added even if not specified.

=item * B<min_new_gid> => I<str>

Set minimum GID when creating new group.

Default is UID

=item * B<min_new_uid> => I<str> (default: 0)

Set minimum UID when creating new user.

=item * B<name>* => I<str>

User name.

=item * B<new_gecos> => I<str> (default: "")

Set gecos (usually, full name) when creating new user.

=item * B<new_home_dir> => I<str>

Set home directory when creating new user, defaults to /home/<username>.

=item * B<new_home_dir_mode> => I<int> (default: 448)

Set permission mode of home dir when creating new user.

=item * B<new_password> => I<str>

Set password when creating new user.

Default is a random password

=item * B<new_shell> => I<str> (default: "/bin/bash")

Set shell when creating new user.

=item * B<not_member_of>* => I<str>

List of Unix group names that the user must NOT be member of.

=item * B<primary_group> => I<str>

Specify user's primary group.

In Unix systems, a user must be a member of at least one group. This group is
referred to as the primary group. By default, primary group name is the same as
the user name. The group will be created if not exists.

=item * B<should_already_exist> => I<bool> (default: 0)

If set to true, require that user already exists.

This can be used to fix user membership, but does not create user when it
doesn't exist.

=item * B<skel_dir> => I<str> (default: "/etc/skel")

Directory to get skeleton files when creating new user.

=item * B<use_skel_dir> => I<bool> (default: 1)

Whether to copy files from skeleton dir when creating new user.

=back

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

