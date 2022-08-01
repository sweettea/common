%define         base_name Pdoc
Name:           perl-%{base_name}
Version:        1.1
Release:        2%{?dist}
Summary:        Perl Pdoc
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
This package contains the Perl Pdoc Modules.

%prep
%setup -q -n common-main

%build
cd packaging/perl-Pdoc
mkdir bin lib
cp -a ../../perl/Pdoc lib/
cp -a ../../perl/bin/pdoc2pod.pl bin/
cp -a ../../perl/bin/genPdocIndex.pl bin/
perl Makefile.PL INSTALLDIRS=vendor
make %{?_smp_mflags}

%install
cd packaging/perl-Pdoc
make pure_install DESTDIR=%{buildroot}
find %{buildroot} -type f -name .packlist -delete
%{_fixperms} -c %{buildroot}

%files
%dir %{perl_vendorlib}/Pdoc/
%{perl_vendorlib}/Pdoc/File.pm
%{perl_vendorlib}/Pdoc/Function.pm
%{perl_vendorlib}/Pdoc/Generator.pm
%{perl_vendorlib}/Pdoc/Location.pm
%{perl_vendorlib}/Pdoc/Makefile
%{perl_vendorlib}/Pdoc/Module.pm
%{perl_vendorlib}/Pdoc/ParamList.pm
%{perl_vendorlib}/Pdoc/Script.pm
%{_bindir}/genPdocIndex.pl
%{_bindir}/pdoc2pod.pl

%changelog
* Tue Apr 05 2022 Andy Walsh <awalsh@redhat.com> - 1.1-2
- Updated pdoc2pod.pl to use FindBin::RealBin.

* Thu Mar 24 2022 Andy Walsh <awalsh@redhat.com> - 1.0-2
- Added utilities

* Sat Dec 04 2021 Andy Walsh <awalsh@redhat.com> - 1.0-1
- Initial build
