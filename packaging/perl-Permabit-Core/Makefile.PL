use ExtUtils::MakeMaker qw(WriteMakefile);

WriteMakefile(
  NAME         => 'Permabit::Core',
  MIN_PERL_VERSION => 5.006,
  META_MERGE => {
    license => ["gpl_2"],
  },
  BUILD_REQUIRES => { "ExtUtils::MakeMaker" => 6.48 },
  VERSION_FROM => "lib/Permabit/MainConstants.pm",
  test         => {},
  clean        => { FILES => '*.bak *.old mibs/*.dump lib/*/*~' },
);
