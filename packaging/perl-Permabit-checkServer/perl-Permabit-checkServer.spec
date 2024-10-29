%define         base_name Permabit-checkServer
Name:           perl-%{base_name}
Version:        1.0
Release:        32%{?dist}
Summary:        Permabit checkServer utility
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
Requires:       perl-Permabit-Triage >= 1.02-21
%if 0%{?rhel} && 0%{?rhel} >= 9
Requires:       python3-pbit-lsb-release
%else
Requires:       redhat-lsb-core
%endif
Requires:       scam

%description
This package contains the Permabit checkServer utility.

%files
%dir %{perl_vendorlib}/Permabit/
%{perl_vendorlib}/Permabit/CheckServer/Constants.pm
%{perl_vendorlib}/Permabit/CheckServer/Constants/Implementation.pm
%{perl_vendorlib}/Permabit/CheckServer/Utils.pm
%{perl_vendorlib}/Permabit/CheckServer/Utils/Implementation.pm
%{perl_vendorlib}/Permabit/Internals/CheckServer/Host.pm
%{_bindir}/checkServer.pl

%package Utils
Summary: Utilities for managing RSVP Resources that depend on checkServer.

%description Utils
This package contains the utilities for maintaining system readiness via
checkServer and RSVP.

%files Utils
%{_bindir}/cleanAndRelease.pl
%{_bindir}/cleanFarm.sh

%prep
%setup -q -n common-main

%build
cd packaging/perl-Permabit-checkServer

mkdir -p bin/ lib/Permabit/CheckServer lib/Permabit/CheckServer/Constants lib/Permabit/CheckServer/Utils
mkdir -p lib/Permabit/Internals/CheckServer

cp -v ../../perl/Permabit/CheckServer/Constants.pm lib/Permabit/CheckServer/
cp -v ../../perl/Permabit/CheckServer/Constants/Implementation.pm lib/Permabit/CheckServer/Constants/
cp -v ../../perl/Permabit/CheckServer/Utils.pm lib/Permabit/CheckServer/
cp -v ../../perl/Permabit/CheckServer/Utils/Implementation.pm lib/Permabit/CheckServer/Utils/
cp -v ../../perl/Permabit/Internals/CheckServer/Host.pm lib/Permabit/Internals/CheckServer/
cp -v ../../perl/bin/checkServer.pl bin/
cp -v ../../perl/bin/cleanAndRelease.pl bin/
cp -v ../../tools/bin/cleanFarm.sh bin/

perl Makefile.PL INSTALLDIRS=vendor
make %{?_smp_mflags}

%install
cd packaging/perl-Permabit-checkServer
make pure_install DESTDIR=%{buildroot}
find %{buildroot} -type f -name .packlist -delete
%{_fixperms} -c %{buildroot}

%changelog
* Tue Oct 29 2024 Chung Chung <cchung@redhat.com> - 1.0-32
- Check if dm_vdo module is installed 

* Wed Jul 31 2024 Chung Chung <cchung@redhat.com> - 1.0-30
- Add support for FEDORANEXT OS class

* Mon Jun 10 2024 Chung Chung <cchung@redhat.com> - 1.0-29
- Remove extra line of checkKExecLoaded test 

* Mon Jun 10 2024 Chung Chung <cchung@redhat.com> - 1.0-29
- Remove kexec check for ossbunsen farms

* Wed May 22 2024 Chung Chung <cchung@redhat.com> - 1.0-28
- Add support for Fedora 40

* Fri Apr 05 2024 Chung Chung <cchung@redhat.com> - 1.0-27
- Remove fio from Constants.pm

* Fri Dec 08 2023 Chung Chung <cchung@redhat.com> - 1.0-26
- Add missing Host.pm installation

* Wed Dec 06 2023 Chung Chung <cchung@redhat.com> - 1.0-25
- Add support for Fedora 39.
- Use perl.yaml file to check internal NFS mount.

* Tue Nov 03 2023 Chung Chung <cchung@redhat.com> - 1.0-24
- Add support for pmifarms

* Tue Oct 03 2023 Chung Chung <cchung@redhat.com> - 1.0-23
- Increase MAX_KERN_LOG_SIZE limit to 100M

* Mon Aug 07 2023 Chung Chung <cchung@redhat.com> - 1.0-22
- Add -f in pgrep for program name longer than 15 characters.

* Thu Jul 13 2023 Ken Raeburn <raeburn@redhat.com> - 1.0-21
- For current RHEL add /u1/zubenelgenubi* to BAD_FILES.

* Mon Jun 25 2023 Ken Raeburn <raeburn@redhat.com> - 1.0-20
- Use python3 in check for vdoInstrumentation module.

* Tue May 09 2023 Chung Chung <cchung@redhat.com> - 1.0-19
- skip ntpd check in FEDORA38

* Fri Apr 21 2023 Chung Chung <cchung@redhat.com> - 1.0-18
- Add checkServer and RSVP support for FEDORA38

* Mon Mar 27 2023 Chung Chung <cchung@redhat.com> - 1.0-17
- Add support for the latest RHEL8 uname format

* Mon Mar 20 2023 Chung Chung <cchung@redhat.com> - 1.0-16
- Add support for the latest RHEL9 uname format

* Fri Jan 20 2023 Chung Chung <cchung@redhat.com> - 1.0-15
- Add Fedora 37 support

* Tue Nov 22 2022 Joe Shimkus <jshimkus@redhat.com> - 1.0-14
- Added /big_file to allowed loop devices.
- Restricted allowed loop devices to Beaker or DevVM only.

* Tue Nov 22 2022 Joe Shimkus <jshimkus@redhat.com> - 1.0-13
- Added support of kernel versions 6.* for Fedora 35/36.

* Tue Nov 08 2022 Joe Shimkus <jshimkus@redhat.com> - 1.0-12
- Remove check for /permabit/release when operating in a Beaker environment;
  the mount point is optional for Beaker and is externally specified when
  needed.

* Thu Sep 22 2022 Joe Shimkus <jshimkush@redhat.com> - 1.0-11
- Made dependency providing lsb_release conditional on RHEL version;
  redhat-lsb-core vs python3-pbit-lsb-release.

* Thu Jun 02 2022 Joe Shimkus <jshimkus@redhat.com> - 1.0-10
- Added Permabit::CheckServer::Utils and
  Permabit::CheckServer::Utils:Implementation.

* Wed Jun 01 2022 Joe Shimkus <jshimkus@redhat.com> - 1.0-9
- Corrected accessing of nfs and redhat servers.
- Parameterized the triage user name and uid.

* Fri May 27 2022 Andy Walsh <awalsh@redhat.com> - 1.0-8
- Major cleanup to checkServer.pl script
- Removed a few unused RSVP classes.
- Added architecture RSVP class enforcement.

* Mon May 23 2022 Joe Shimkus <jshimkus@redhat.com> - 1.0-7
- Added creation of CheckServer/Constants subdir.
- Added minimum requirement of Permabit::Triage at 1.02-21.

* Tue May 17 2022 Joe Shimkus <jshimkus@redhat.com> - 1.0-6
- Made Permabit::CheckServer::Constants configurable via an implementation
  helper class.

* Tue May 17 2022 Andy Walsh <awalsh@redhat.com> - 1.0-5
- Added Fedora36 support.
- Updated permatest check.
- Replaced tabs with spaces.

* Fri Apr 08 2022 Andy Walsh <awalsh@redhat.com> - 1.0-4
- Added some utilities for managing farm cleanup provided as a sub-package

* Mon Apr 04 2022 Bruce Johnston <bjohnsto@redhat.com> - 1.0-3
- Move perl files from tools/bin to perl/bin.

* Tue Feb 22 2022 Andy Walsh <awalsh@redhat.com> - 1.0-2
- Fixed up perl module naming to be a Permabit submodule.

* Tue Feb 22 2022 Andy Walsh <awalsh@redhat.com> - 1.0-1
- Initial build
