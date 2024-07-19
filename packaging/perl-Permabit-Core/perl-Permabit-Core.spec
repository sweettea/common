%define         base_name Permabit-Core
Name:           perl-%{base_name}
Version:        1.03
Release:        45%{?dist}
Summary:        Permabit Core Perl libs
License:        GPL2+
URL:            https://github.com/dm-vdo/common
Source0:        %{url}/archive/refs/heads/main.tar.gz
BuildArch:      noarch
# Module Build
BuildRequires:  coreutils
BuildRequires:  findutils
BuildRequires:  make
BuildRequires:  perl-generators
BuildRequires:  perl-interpreter
BuildRequires:  perl(ExtUtils::MakeMaker)
# Module Runtime
BuildRequires:  perl(Carp)
%if ! 0%{?rhel} && ! 0%{?eln}
BuildRequires:  perl(Clone) >= 0.43
%endif
BuildRequires:  perl(Cwd)
BuildRequires:  perl(Exporter)
BuildRequires:  perl(File::Find::Rule)
BuildRequires:  perl(Scalar::Util)
BuildRequires:  perl(strict)
BuildRequires:  perl(vars)
BuildRequires:  perl(warnings)
# Test Suite
BuildRequires:  perl(Config)
BuildRequires:  perl(constant)
BuildRequires:  perl(Data::Dumper)
BuildRequires:  perl(Test::More) >= 0.88
# Optional Tests
BuildRequires:  perl(JSON)
%if ! 0%{?rhel} && ! 0%{?eln}
BuildRequires:  perl(Scalar::Properties)
%endif
BuildRequires:  perl(Test::Pod) >= 1.00
# Dependencies
Requires:       perl(:MODULE_COMPAT_%(eval "`perl -V:version`"; echo $version))

%description
This package contains the core Permabit libraries.

%package -n perl-Permabit-Assertions
Summary:        Permabit Assertions Perl Module

%description -n perl-Permabit-Assertions
This package contains the Permabit Perl Assertions module.

%files -n perl-Permabit-Assertions
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/Assertions.pm

%package -n perl-Permabit-AsyncSub
Summary: perl-Permabit-Async stubfile
Requires: perl-Permabit-Async

%description -n perl-Permabit-AsyncSub
This is a dummy package that is intended to maintain backward compatibility for
prior installations.  It will pull in perl-Permabit-Async as a dependency which
directly replaces this package in its previous form.

%package -n perl-Permabit-Async
Summary:        Permabit Async Perl Modules

%description -n perl-Permabit-Async
This package contains the Permabit Perl AsyncSub module.

%files -n perl-Permabit-Async
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/AsyncSub.pm
%{perl_vendorlib}/Permabit/AsyncTask.pm
%{perl_vendorlib}/Permabit/AsyncTask/LoopRunSystemCmd.pm
%{perl_vendorlib}/Permabit/AsyncTask/Makefile
%{perl_vendorlib}/Permabit/AsyncTask/RunSystemCmd.pm
%{perl_vendorlib}/Permabit/AsyncTasks.pm

%package -n perl-Permabit-BashSession
Summary:        Permabit BashSession Perl Module

%description -n perl-Permabit-BashSession
This package contains the Permabit Perl BashSession module.

%files -n perl-Permabit-BashSession
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/BashSession.pm

%package -n perl-Permabit-BinaryFinder
Summary:        Permabit BinaryFinder Perl Module

%description -n perl-Permabit-BinaryFinder
This package contains the Permabit Perl BinaryFinder module.

%files -n perl-Permabit-BinaryFinder
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/BinaryFinder.pm

%package -n perl-Permabit-CommandString
Summary:        Permabit CommandString Perl Module

%description -n perl-Permabit-CommandString
This package contains the Permabit Perl CommandString module.

%files -n perl-Permabit-CommandString
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/CommandString.pm

%package -n perl-Permabit-Configured
Summary:        Permabit Configured Perl Module

%description -n perl-Permabit-Configured
This package contains the Permabit Perl Configured module.

%files -n perl-Permabit-Configured
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/Configured.pm
%{perl_vendorlib}/Permabit/ConfiguredFactory.pm
%{perl_vendorlib}/Permabit/ConfiguredFactory.yaml
%config(noreplace) %{perl_vendorlib}/Permabit/perl.yaml
%dir %{_sysconfdir}/permabit
%{_sysconfdir}/permabit/perl.yaml

%package -n perl-Permabit-Constants
Summary:        Permabit Constants Perl Module

%description -n perl-Permabit-Constants
This package contains the Permabit Perl Constants module.

%files -n perl-Permabit-Constants
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/Constants.pm
%{perl_vendorlib}/Permabit/MainConstants.pm
%{perl_vendorlib}/Permabit/MainConstants/Implementation.pm

%package -n perl-Permabit-CurrentVersionFile
Summary:        Permabit CurrentVersionFile Perl Module

%description -n perl-Permabit-CurrentVersionFile
This package contains the Permabit Perl CurrentVersionFile module.

%files -n perl-Permabit-CurrentVersionFile
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/CurrentVersionFile.pm

%package -n perl-Permabit-Exception
Summary:        Permabit Exception Perl Module

%description -n perl-Permabit-Exception
This package contains the Permabit Perl Exception module.

%files -n perl-Permabit-Exception
%{perl_vendorlib}/Permabit/Exception.pm

%package -n perl-Permabit-FileCopier
Summary:        Permabit FileCopier Perl Module

%description -n perl-Permabit-FileCopier
This package contains the Permabit Perl FileCopier module.

%files -n perl-Permabit-FileCopier
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/FileCopier.pm

%package -n perl-Permabit-Future
Summary:        Permabit Future Perl Module

%description -n perl-Permabit-Future
This package contains the Permabit Perl Future module.

%files -n perl-Permabit-Future
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/Future.pm
%{perl_vendorlib}/Permabit/Future/AfterAsyncSub.pm
%{perl_vendorlib}/Permabit/Future/AfterFuture.pm
%{perl_vendorlib}/Permabit/Future/AnyOrder.pm
%{perl_vendorlib}/Permabit/Future/InOrder.pm
%{perl_vendorlib}/Permabit/Future/List.pm
%{perl_vendorlib}/Permabit/Future/Timer.pm

%package -n perl-Permabit-INETSocket
Summary:        Permabit INETSocket Perl Module

%description -n perl-Permabit-INETSocket
This package contains the Permabit Perl INETSocket module.

%files -n perl-Permabit-INETSocket
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/INETSocket.pm

%package -n perl-Permabit-Jira
Summary:        Permabit Jira Perl Module

%description -n perl-Permabit-Jira
This package contains the Permabit Perl Jira modules.

%files -n perl-Permabit-Jira
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/Jira.pm

%package -n perl-Permabit-NotUsed
Summary:        Permabit Perl Modules that are not expected to be used.

%description -n perl-Permabit-NotUsed
This package contains Permabit Perl Modules that do not appear to be required
to run anything in the environments required by VDO.

%files -n perl-Permabit-NotUsed
%{perl_vendorlib}/Permabit/.runtests.options
%{perl_vendorlib}/Permabit/CheckServer/Constants.pm
%{perl_vendorlib}/Permabit/CheckServer/Constants/Implementation.pm
%{perl_vendorlib}/Permabit/CheckServer/Makefile
%{perl_vendorlib}/Permabit/CheckServer/Utils.pm
%{perl_vendorlib}/Permabit/CheckServer/Utils/Implementation.pm
%{perl_vendorlib}/Permabit/Future/Makefile
%{perl_vendorlib}/Permabit/Internals/CheckServer/Host.pm
%{perl_vendorlib}/Permabit/testcases/Assertions_t1.pm
%{perl_vendorlib}/Permabit/testcases/AsyncSubTest.pm
%{perl_vendorlib}/Permabit/testcases/BindUtils_t1.pm
%{perl_vendorlib}/Permabit/testcases/CheckServer_t1.pm
%{perl_vendorlib}/Permabit/testcases/CheckServer_t1.yaml
%{perl_vendorlib}/Permabit/testcases/ClassUtils_t1.pm
%{perl_vendorlib}/Permabit/testcases/CommandStringDF.pm
%{perl_vendorlib}/Permabit/testcases/CommandString_t1.pm
%{perl_vendorlib}/Permabit/testcases/ConfiguredFactory_t1.pm
%{perl_vendorlib}/Permabit/testcases/ConfiguredFactory_t1.yaml
%{perl_vendorlib}/Permabit/testcases/Configured_t1.pm
%{perl_vendorlib}/Permabit/testcases/Configured_t1.yaml
%{perl_vendorlib}/Permabit/testcases/configured_t1/EnabledPath.pm
%{perl_vendorlib}/Permabit/testcases/Duration_t1.pm
%{perl_vendorlib}/Permabit/testcases/Exception_t1.pm
%{perl_vendorlib}/Permabit/testcases/Future_t1.pm
%{perl_vendorlib}/Permabit/testcases/LabUtils_t1.pm
%{perl_vendorlib}/Permabit/testcases/LabUtils_t1.yaml
%{perl_vendorlib}/Permabit/testcases/LastrunUpdater_t1.pm
%{perl_vendorlib}/Permabit/testcases/Makefile
%{perl_vendorlib}/Permabit/testcases/Options_t1.pm
%{perl_vendorlib}/Permabit/testcases/PlatformUtils_t1.pm
%{perl_vendorlib}/Permabit/testcases/ProcSimpleTest.pm
%{perl_vendorlib}/Permabit/testcases/ProcessUtils_t1.pm
%{perl_vendorlib}/Permabit/testcases/RSVP_t1.pm
%{perl_vendorlib}/Permabit/testcases/RSVPer_t1.pm
%{perl_vendorlib}/Permabit/testcases/RebootMachine.pm
%{perl_vendorlib}/Permabit/testcases/RegexpHash_t1.pm
%{perl_vendorlib}/Permabit/testcases/RemoteMachineBase.pm
%{perl_vendorlib}/Permabit/testcases/RemoteMachine_t1.pm
%{perl_vendorlib}/Permabit/testcases/RemoteMachine_t2.pm
%{perl_vendorlib}/Permabit/testcases/RemoteMachine_t3.pm
%{perl_vendorlib}/Permabit/testcases/ReserveHostGroup.pm
%{perl_vendorlib}/Permabit/testcases/SSHMuxIPCSession_t1.pm
%{perl_vendorlib}/Permabit/testcases/Sort_t1.pm
%{perl_vendorlib}/Permabit/testcases/SupportUtils_t1.pm
%{perl_vendorlib}/Permabit/testcases/SystemUtils_t1.pm
%{perl_vendorlib}/Permabit/testcases/SystemUtils_t1.yaml
%{perl_vendorlib}/Permabit/testcases/Tempfile_t1.pm
%{perl_vendorlib}/Permabit/testcases/TestcaseTest.pm
%{perl_vendorlib}/Permabit/testcases/TimeoutDummyTest.pm
%{perl_vendorlib}/Permabit/testcases/TriageUtils_t1.pm
%{perl_vendorlib}/Permabit/testcases/Utils_t1.pm
%{perl_vendorlib}/Permabit/testcases/VersionNumber_t1.pm
%{perl_vendorlib}/Permabit/testcases/log.conf
%{perl_vendorlib}/Permabit/testcases/log.conf.nightly
%{perl_vendorlib}/Permabit/testcases/suites

%files
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/BindUtils.pm
%{perl_vendorlib}/Permabit/Duration.pm
%{perl_vendorlib}/Permabit/InetdUtils.pm
%{perl_vendorlib}/Permabit/LastrunUpdater.pm
%{perl_vendorlib}/Permabit/Log4perlUtils.pm
%{perl_vendorlib}/Permabit/Makefile
%{perl_vendorlib}/Permabit/RegexpHash.pm
%{perl_vendorlib}/Permabit/Regexps.pm
%{perl_vendorlib}/Permabit/Unimplemented.pm

%package -n perl-Permabit-Options
Summary:        Permabit Options Module

%description -n perl-Permabit-Options
This package contains the Permabit Perl Options modules.

%files -n perl-Permabit-Options
%{perl_vendorlib}/Permabit/Options.pm

%package -n perl-Permabit-Parameterizer
Summary:        Permabit Parameterizer Perl Module

%description -n perl-Permabit-Parameterizer
This package contains the Permabit Perl Parameterizer modules.

%files -n perl-Permabit-Parameterizer
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/Parameterizer.pm

%package -n perl-Permabit-Propertied
Summary:        Permabit Propertied Perl Module

%description -n perl-Permabit-Propertied
This package contains the Permabit Perl Propertied module.

%files -n perl-Permabit-Propertied
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/Propertied.pm

%package -n perl-Permabit-RemoteMachine
Summary:        Permabit RemoteMachine Perl Module

%description -n perl-Permabit-RemoteMachine
This package contains the Permabit Perl RemoteMachine module.

%files -n perl-Permabit-RemoteMachine
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/RemoteMachine.pm

%package -n perl-Permabit-RSVP
Summary:        Permabit RSVP Perl Module
%if 0%{?rhel} && 0%{?rhel} >= 9
Requires:       python3-pbit-lsb-release
%else
Requires:       redhat-lsb-core
%endif

%description -n perl-Permabit-RSVP
This package contains the Permabit Perl RSVP modules.

%files -n perl-Permabit-RSVP
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/RSVP.pm
%{perl_vendorlib}/Permabit/RSVPer.pm

%package -n perl-Permabit-SSHMuxIPCSession
Summary:        Permabit SSHMuxIPCSession Perl Module

%description -n perl-Permabit-SSHMuxIPCSession
This package contains the Permabit Perl SSHMuxIPCSession modules.

%files -n perl-Permabit-SSHMuxIPCSession
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/SSHMuxIPCSession.pm

%package -n perl-Permabit-TempFile
Summary:        Permabit TempFile Perl Module

%description -n perl-Permabit-TempFile
This package contains the Permabit Perl TempFile module.

%files -n perl-Permabit-TempFile
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/Tempfile.pm

%package -n perl-Permabit-Testcase
Summary:        Permabit Testcase Perl Module

%description -n perl-Permabit-Testcase
This package contains the Permabit Perl Testcase module.

%files -n perl-Permabit-Testcase
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/Testcase.pm

%package -n perl-Permabit-TestRunner
Summary:        Permabit TestRunner Perl Module

%description -n perl-Permabit-TestRunner
This package contains the Permabit Perl TestRunner module.

%files -n perl-Permabit-TestRunner
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/TestRunner.pm
%{perl_vendorlib}/Permabit/XMLFormatter.pm
%{perl_vendorlib}/Permabit/XMLTestRunner.pm

%package -n perl-Permabit-Triage
Summary:        Permabit Triage Perl Module

%description -n perl-Permabit-Triage
This package contains the Permabit Perl Triage modules.

%files -n perl-Permabit-Triage
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/Triage/TestInfo.pm
%{perl_vendorlib}/Permabit/Triage/TestInfo/Implementation.pm
%{perl_vendorlib}/Permabit/Triage/Utils.pm
%{perl_vendorlib}/Permabit/Triage/Utils/Implementation.pm

%package -n perl-Permabit-Utils
Summary:        Permabit Utils Perl Module

%description -n perl-Permabit-Utils
This package contains the Permabit Perl Utils module.

%files -n perl-Permabit-Utils
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/ClassUtils.pm
%{perl_vendorlib}/Permabit/LabUtils.pm
%{perl_vendorlib}/Permabit/LabUtils/Implementation.pm
%{perl_vendorlib}/Permabit/LabUtils/LabMachine.pm
%{perl_vendorlib}/Permabit/LabUtils/Makefile
%{perl_vendorlib}/Permabit/PlatformUtils.pm
%{perl_vendorlib}/Permabit/ProcessUtils.pm
%{perl_vendorlib}/Permabit/SupportUtils.pm
%{perl_vendorlib}/Permabit/SystemUtils.pm
%{perl_vendorlib}/Permabit/SystemUtils/Implementation.pm
%{perl_vendorlib}/Permabit/Utils.pm
%{perl_vendorlib}/Permabit/Utils/Implementation.pm

%package -n perl-Permabit-VersionNumber
Summary:        Permabit VersionNumber Perl Module

%description -n perl-Permabit-VersionNumber
This package contains the Permabit Perl VersionNumber module.

%files -n perl-Permabit-VersionNumber
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/VersionNumber.pm
%{perl_vendorlib}/Permabit/VersionNumber/First.pm
%{perl_vendorlib}/Permabit/VersionNumber/Last.pm
%{perl_vendorlib}/Permabit/VersionNumber/Special.pm

%prep
%setup -q -n common-main

%build
cd packaging/perl-Permabit-Core
mkdir lib
cp -a ../../perl/Permabit lib/

# Remove runtests.pl symlinks because MakeMaker tries to build them
rm lib/Permabit/TestDispatch/runtests.pl lib/Permabit/runtests.pl

perl Makefile.PL INSTALLDIRS=vendor
make %{?_smp_mflags}

%install
cd packaging/perl-Permabit-Core
make pure_install DESTDIR=%{buildroot}
find %{buildroot} -type f -name .packlist -delete
%{_fixperms} -c %{buildroot}

# Install the default configuration file into the default location.
%{__install} -m 644 -D lib/Permabit/ConfiguredFactory.yaml $RPM_BUILD_ROOT/%{_sysconfdir}/permabit/perl.yaml

%changelog
* Fri Jul 19 2024 Andy Walsh <awalsh@redhat.com> - 1.03-45
- Testcase.pm: Use updated script to capture console logs

* Mon Jun 10 2024 Andy Walsh <awalsh@redhat.com> - 1.03-44
- RSVP.pm: Verify host ownership before releasing

* Wed May 22 2024 Chung Chung <cchung@redhat.com> - 1.03-43
- Add FEDORA40 to RSVP OS list in ConfiguredFactory.yaml 

* Mon Jan 22 2024 Chung Chung <cchung@redhat.com> - 1.03-42
- Update RSVP.pm to add '(DISTRO:OS)' in rsvp message.

* Wed Dec 13 2023 Chung Chung <cchung@redhat.com> - 1.03-41
- Update ConfiguredFactory.yaml with default Internals session.

* Wed Dec 13 2023 Chung Chung <cchung@redhat.com> - 1.03-40
- Add Permabit/Internals/CheckServer/Host.pm to perl-Permabit-NotUsed list.

* Thu Jul 06 2023 Joe Shimkus <jshimkus@redhat.com> - 1.03-39
- Changed determination of LabMachine reboot to use boot_id.

* Wed Jul 05 2023 Chung Chung <cchung@redhat.com> - 1.03-38
- Replace fgrep with 'grep -F' in RemoteMachine.pm.

* Wed Jul 05 2023 Michael Sclafani <sclafani@redhat.com> - 1.03-37
- Remove unused references in Utils.pm and TestInfo.pm.

* Wed Jul 05 2023 Corwin Coburn <corwin@redhat.com> - 1.03-36
- Add log of version file contents.

* Tue Jun 06 2023 Susan LeGendre-McGhee <slegendr@redhat.com> - 1.03-35
- Add RemoteMachine userBinaryDir property.
- At CommandString instantiation, if not already defined, get userBinaryDir
  from RemoteMachine.

* Mon Jun 05 2023 Susan LeGendre-McGhee <slegendr@redhat.com> - 1.03-34
- Add storageDevice and userBinaryDir as CommandString inherited properties.

* Fri Apr 21 2023 Chung Chung <cchung@redhat.com> - 1.03-33
- Add Fedora 38 support.

* Fri Jan 20 2023 Chung Chung <cchung@redhat.com> - 1.03-32
- Add Fedora 37 support.

* Thu Oct 13 2022 Joe Shimkus <jshimkush@redhat.com> - 1.03-31
- Add lsb_release provider dependency to perl-Permabit-RSVP.

* Fri Sep 09 2022 Joe Shimkus <jshimkush@redhat.com> - 1.03-30
- Updated RSVP_t1.pm for obsoleted classes.

* Fri Sep 09 2022 Joe Shimkus <jshimkush@redhat.com> - 1.03-29
- Support regexes in RSVP.pm check of allowable user processes.

* Fri Sep 02 2022 Joe Shimkus <jshimkush@redhat.com> - 1.03-28
- Changed RSVP.pm to get classes and processes from config file.

* Fri Aug 26 2022 Joe Shimkus <jshimkush@redhat.com> - 1.03-27
- Added runtime query of machine class to Permabit::RSVP.pm; allows
  dynamic specification of allowable processes.

* Fri Aug 05 2022 Andy Walsh <awalsh@redhat.com> - 1.03-26
- Fix ossbunsen SSHMuxIPCSession issue.
- Testcase.pm: Remove typeNames property and references.
- RSVPer.pm: Add the ability to get the RSVP architecture of a host.

* Thu Jun 02 2022 Joe Shimkus <jshimkus@redhat.com> - 1.02-26
- Added Permabit::CheckServer::Utils and
  Permabit::CheckServer::Utils:Implementation.

* Mon May 23 2022 Joe Shimkus <jshimkus@redhat.com> - 1.02-25
- Modified Permabit::Testcase and Permabit::ConfiguredFactory.pm to
  auto-determine and process test-specific configuration overrides.

* Thu May 19 2022 Joe Shimkus <jshimkus@redhat.com> - 1.02-24
- Made Permabit::LabUtils configurable via an implementation helper class.

* Thu May 19 2022 Joe Shimkus <jshimkus@redhat.com> - 1.02-23
- Made Permabit::MainConstants configurable via an implementation helper class.

* Thu May 19 2022 Joe Shimkus <jshimkus@redhat.com> - 1.02-22
- Made Permabit::Triage::Utils configurable via an implementation helper
  class.

* Tue May 17 2022 Joe Shimkus <jshimkus@redhat.com> - 1.02-21
- Made Permabit::Triage::TestInfo configurable via an implementation helper
  class.

* Tue May 17 2022 Joe Shimkus <jshimkus@redhat.com> - 1.02-20
- Made Permabit::SystemUtils configurable via an implementation helper class.

* Tue May 17 2022 Joe Shimkus <jshimkus@redhat.com> - 1.02-19
- Made Permabit::CheckServer::Constants configurable via an implementation
  helper class.

* Thu May 12 2022 corwin <corwin@redhat.com> - 1.02-18
- Made Permabit::Utils configurable via an implementation helper class.

* Mon Apr 25 2022 Joe Shimkus <jshimkus@redhat.com> - 1.02-17
- Remove IPMIenabled from //eng/common.

* Wed Apr 20 2022 Bruce Johnston <bjohnsto@redhat.com> - 1.02-16
- Remove unused files from //eng/common.

* Tue Apr 19 2022 Bruce Johnston <bjohnsto@redhat.com> - 1.02-15
- Remove perforce from //eng/common.

* Tue Apr 19 2022 Bruce Johnston <bjohnsto@redhat.com> - 1.02-14
- Remove files that were moved to //eng/linux-vdo.

* Sun Apr 17 2022 Andy Walsh <awalsh@redhat.com> - 1.02-13
- Marked perl config file as a configuration file not to be replaced
  automatically.

* Thu Apr 14 2022 Andy Walsh <awalsh@redhat.com> - 1.02-12
- Converted configuration message to only output with debug

* Tue Apr 12 2022 Andy Walsh <awalsh@redhat.com> - 1.01-12
- Split out Permabit::CurrentVersionFile into a new sub-package.
- Added Permabit::CheckServer files to perl-Permabit-NotUsed as they are
  provided via a different package.
- Dropped Permabit::Grub, Permabit::KernelModule, and Permabit::Statistic from
  perl-Permabit-Core

* Sun Apr 03 2022 Andy Walsh <awalsh@redhat.com> - 1.01-11
- Split out Permabit::Future into a new sub-package.

* Thu Mar 31 2022 Andy Walsh <awalsh@redhat.com> - 1.01-10
- Split out Permabit::CommandString into a new sub-package.

* Wed Mar 30 2022 Andy Walsh <awalsh@redhat.com> - 1.01-9
- Split out Permabit::Async*, Permabit::BashSession, Permabit::Exception,
  Permabit::Options, Permabit::RemoteMachine, Permabit::RSVPer (into
  perl-Permabit-RSVP), Permabit::TestCase, and Permabit::VersionNumber into new
  sub-packages.

* Tue Mar 22 2022 Andy Walsh <awalsh@redhat.com> - 1.01-8
- Split out Permabit::FileCopier and Permabit::TestRunner from Core

* Tue Mar 22 2022 Andy Walsh <awalsh@redhat.com> - 1.01-7
- Split out Permabit::P4 and Permabit::Propertied

* Wed Mar 09 2022 Andy Walsh <awalsh@redhat.com> - 1.01-6
- Removed several unused files from the Core list

* Wed Mar 02 2022 Ken Raeburn <raeburn@redhat.com> - 1.01-5
- Removed several unused files from the NotUsed list

* Tue Feb 22 2022 Andy Walsh <awalsh@redhat.com> - 1.01-4
- Added Permabit::TempFile

* Tue Feb 22 2022 Andy Walsh <awalsh@redhat.com> - 1.01-3
- Added Permabit::Configured

* Tue Feb 22 2022 Andy Walsh <awalsh@redhat.com> - 1.01-2
- Added Permabit::AsyncSub

* Sat Dec 04 2021 Andy Walsh <awalsh@redhat.com> - 1.01-1
- Initial build
