use 5.005;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'WWW::RobotRules::MySQLCache',
    VERSION_FROM      => 'lib/WWW/RobotRules/MySQLCache.pm', # finds $VERSION
    PREREQ_PM         => {
     'DateTime::Format::Epoch' => 0,
     DBI =>0,
     'LWP::Simple'=>0,
     'WWW::RobotRules::Parser'=>0,
    }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/WWW/RobotRules/MySQLCache.pm', # retrieve abstract from module
       AUTHOR         => 'A. M. Patwa <ankur@uccs.edu>') : ()),
);
