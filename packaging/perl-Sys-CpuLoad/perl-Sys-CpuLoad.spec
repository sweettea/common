Name:           perl-Sys-CpuLoad
Version:        0.31
Release:        1%{?dist}
Summary:        retrieve system load averages
License:        GPL+ or Artistic
URL:            https://metacpan.org/pod/Sys::CpuLoad
Source0:        https://cpan.metacpan.org/authors/id/R/RR/RRWO/Sys-CpuLoad-%{version}.tar.gz
# Module Build
BuildRequires:  coreutils
BuildRequires:  findutils
BuildRequires:  make
BuildRequires:  gcc
BuildRequires:  perl-generators
BuildRequires:  perl-interpreter
BuildRequires:  perl-devel
BuildRequires:  perl(ExtUtils::MakeMaker)
BuildRequires:  perl(ExtUtils::Constant)
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
BuildRequires:  perl(Data::Dumper)
BuildRequires:  perl(File::Which) >= 1.23
BuildRequires:  perl(IPC::Run3) >= 0.048
BuildRequires:  perl(Module::Metadata) >= 1.000037
%if ! 0%{?rhel} && ! 0%{?eln}
BuildRequires:  perl(Test::Deep) >= 1.130
%endif
BuildRequires:  perl(Test::Exception) >= 0.43
BuildRequires:  perl(Test::More) >= 0.88
%if ! 0%{?rhel} && ! 0%{?eln}
BuildRequires:  perl(Test::Warnings) >= 0.030
%endif
BuildRequires:  perl(constant)
# Optional Tests
BuildRequires:  perl(JSON)
BuildRequires:  perl(Scalar::Properties)
BuildRequires:  perl(Test::Pod) >= 1.00
# Dependencies
Requires:       perl(:MODULE_COMPAT_%(eval "`perl -V:version`"; echo $version))

%description
This module retrieves the 1 minute, 5 minute, and 15 minute load average of a
machine.

%prep
%setup -q -n Sys-CpuLoad-%{version}

%build
perl Makefile.PL INSTALLDIRS=vendor
make %{?_smp_mflags}

%install
make pure_install DESTDIR=%{buildroot}
find %{buildroot} -type f -name .packlist -delete
%{_fixperms} -c %{buildroot}

%check
make test

%files
%license LICENSE
%doc Changes README.md
%dir %{perl_vendorarch}/Sys/
%{perl_vendorarch}/Sys/CpuLoad.pm
#XXX: These need to be converted to the right macros
/usr/lib64/perl5/vendor_perl/auto/Sys/CpuLoad/CpuLoad.so
/usr/share/man/man3/Sys::CpuLoad.3pm.gz

%changelog
* Sun Dec 05 2021 Andy Walsh <awalsh@redhat.com> - 0.31-1
- Initial build
