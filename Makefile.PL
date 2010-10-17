use ExtUtils::MakeMaker;

WriteMakefile(
	NAME              => 'Text::Extract::Word',
	VERSION_FROM      => 'lib/Text/Extract/Word.pm',
    ABSTRACT_FROM     => 'lib/Text/Extract/Word.pm',
	AUTHOR            => 'Stuart Watt <stuart@morungos.com>',
    MIN_PERL_VERSION  => '5.8.0',
    LICENSE           => 'artistic',
	PREREQ_PM         => { 'OLE::Storage_Lite' => 0,
	                       'POSIX'             => 0,
	                       'IO::File'          => 0,
	                       'Encode'            => 0 },           
);