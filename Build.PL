
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  'build_requires' => {
    'Module::Build' => '0.3601'
  },
  'configure_requires' => {
    'Module::Build' => '0.3601'
  },
  'dist_abstract' => 'Setup Unix user (existence, group memberships)',
  'dist_author' => [
    'Steven Haryanto <stevenharyanto@gmail.com>'
  ],
  'dist_name' => 'Setup-Unix-User',
  'dist_version' => '0.06',
  'license' => 'perl',
  'module_name' => 'Setup::Unix::User',
  'recommends' => {},
  'recursive_test_files' => 1,
  'requires' => {
    'File::Slurp' => '0',
    'File::chdir' => '0',
    'Log::Any' => '0',
    'Passwd::Unix::Alt' => '0.5205',
    'Setup::File' => '0',
    'Sub::Spec' => '0.13',
    'Test::More' => '0.96',
    'Text::Password::Pronounceable' => '0',
    'perl' => '5.010000'
  },
  'script_files' => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
