Name:           p4perl
Version:        2021.1.2185795
Release:        1%{?dist}
Summary:        P4 Perl
Group:          System Environment/Base
License:        Commercial
URL:            https://github.com/perforce/p4perl
Source0:        https://ftp.perforce.com/perforce/r21.1/bin.tools/p4perl.tgz
Source1:        https://ftp.perforce.com/perforce/r21.1/bin.linux26x86_64/p4api.tgz
Requires:       make
Requires:       openssl
# Dependencies
Requires:       perl(:MODULE_COMPAT_%(eval "`perl -V:version`"; echo $version))
BuildRequires:  coreutils
BuildRequires:  findutils
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  openssl-devel
BuildRequires:  perl(English)
BuildRequires:  perl(ExtUtils::MakeMaker)
BuildRequires:  perl-devel
BuildRequires:  perl-generators

%description
P4 Perl Module

%prep
%setup -q -n %{name}-%{version}
cd ..
# Unpack the p4api to use while building p4perl.
tar xzf %{SOURCE1}

%build
# Unfortunately, the version for p4api isn't reflected in the tarball name, so
# we can't do much more than just unpack it and reference it directly like
# this.
perl Makefile.PL --apidir=../p4api-2021.1.2242478/ INSTALLDIRS=vendor
make  %{?_smp_mflags}

%install
make pure_install DESTDIR=%{buildroot}
find %{buildroot} -type f -name .packlist -delete
%{_fixperms} -c %{buildroot}

%files
%{_libdir}/perl5/vendor_perl/P4.pm
%{_libdir}/perl5/vendor_perl/P4/DepotFile.pm
%{_libdir}/perl5/vendor_perl/P4/Integration.pm
%{_libdir}/perl5/vendor_perl/P4/IterateSpec.pm
%{_libdir}/perl5/vendor_perl/P4/Map.pm
%{_libdir}/perl5/vendor_perl/P4/MergeData.pm
%{_libdir}/perl5/vendor_perl/P4/Message.pm
%{_libdir}/perl5/vendor_perl/P4/OutputHandler.pm
%{_libdir}/perl5/vendor_perl/P4/Progress.pm
%{_libdir}/perl5/vendor_perl/P4/Resolver.pm
%{_libdir}/perl5/vendor_perl/P4/Revision.pm
%{_libdir}/perl5/vendor_perl/P4/Spec.pm
%{_libdir}/perl5/vendor_perl/auto/P4/DepotFile/autosplit.ix
%{_libdir}/perl5/vendor_perl/auto/P4/Integration/autosplit.ix
%{_libdir}/perl5/vendor_perl/auto/P4/P4.so
%{_libdir}/perl5/vendor_perl/auto/P4/Revision/autosplit.ix
%{_libdir}/perl5/vendor_perl/auto/P4/Spec/autosplit.ix
%{_libdir}/perl5/vendor_perl/auto/P4/autosplit.ix
%{_mandir}/man3/P4.3pm.gz
%{_mandir}/man3/P4::DepotFile.3pm.gz
%{_mandir}/man3/P4::Integration.3pm.gz
%{_mandir}/man3/P4::IterateSpec.3pm.gz
%{_mandir}/man3/P4::Map.3pm.gz
%{_mandir}/man3/P4::MergeData.3pm.gz
%{_mandir}/man3/P4::Message.3pm.gz
%{_mandir}/man3/P4::OutputHandler.3pm.gz
%{_mandir}/man3/P4::Progress.3pm.gz
%{_mandir}/man3/P4::Resolver.3pm.gz
%{_mandir}/man3/P4::Revision.3pm.gz
%{_mandir}/man3/P4::Spec.3pm.gz

%changelog
* Tue Mar 22 2022 Andy Walsh <awalsh@redhat.com> - 2021.1.2185795
- Initial build
