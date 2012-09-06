
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Crypt::Password::Util" => 0,
    "File::Copy::Recursive" => 0,
    "File::Slurp" => 0,
    "File::chdir" => 0,
    "Module::Build" => "0.3601",
    "Test::More" => "0.98",
    "Test::Perinci::Tx::Manager" => 0
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Setup Unix user (existence, home dir, group memberships)",
  "dist_author" => [
    "Steven Haryanto <stevenharyanto\@gmail.com>"
  ],
  "dist_name" => "Setup-Unix-User",
  "dist_version" => "0.10",
  "license" => "perl",
  "module_name" => "Setup::Unix::User",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "File::Copy::Undoable" => "0.02",
    "File::Trash::Undoable" => 0,
    "Log::Any" => 0,
    "PerlX::Maybe" => 0,
    "Rinci" => "v1.1.28",
    "Setup" => "v1.0.3",
    "Setup::File" => 0,
    "Text::Password::Pronounceable" => 0,
    "Unix::Passwd::File" => "0.07",
    "perl" => "5.010001"
  },
  "script_files" => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
