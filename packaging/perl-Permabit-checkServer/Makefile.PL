use ExtUtils::MakeMaker qw(WriteMakefile);

WriteMakefile(
  NAME         => 'Permabit::CheckServer',
  MIN_PERL_VERSION => 5.006,
  META_MERGE => {
    license => ["gpl_2"],
  },
  BUILD_REQUIRES => { "ExtUtils::MakeMaker" => 6.48 },
  VERSION      => "1.0",
  test         => {},
  clean        => { FILES => '*.bak *.old mibs/*.dump lib/*/*~' },
  EXE_FILES    => ['bin/checkServer.pl',
                   'bin/cleanFarm.sh',
                   'bin/cleanAndRelease.pl'],
);
