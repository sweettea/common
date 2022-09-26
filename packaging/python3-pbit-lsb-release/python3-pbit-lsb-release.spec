%define repo_name common
%define repo_branch main

%define name python3-pbit-lsb-release
%define version 1.0.2
%define unmangled_version 1.0.2
%define release 1

Summary: %{name}
Name: %{name}
Version: %{version}
Release: %{release}
URL:     https://github.com/dm-vdo/common
Source0: %{url}/archive/refs/heads/main.tar.gz
License: GPL2+
Group: Development/Libraries
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Prefix: %{_prefix}
BuildArch: noarch

%if 0%{?rhel} && 0%{?rhel} < 9
BuildRequires: python39
BuildRequires: python39-setuptools
Requires: python39
%else
BuildRequires: python3
BuildRequires: python3-setuptools
Requires: python3
%endif

%description
UNKNOWN

AutoProv: no
Provides: lsb_release
Conflicts: lsb_release

%prep
%setup -n %{repo_name}-%{repo_branch}

%build
(cd python/pbit_lsb_release && python3 setup.py build)

%install
(cd python/pbit_lsb_release && \
  python3 setup.py install --single-version-externally-managed -O1 \
    --root=$RPM_BUILD_ROOT --record=INSTALLED_FILES \
    --install-scripts %{_bindir})

%clean
rm -rf $RPM_BUILD_ROOT

%files -f python/pbit_lsb_release/INSTALLED_FILES
%defattr(-,root,root)

%changelog
* Thu Sep 22 2022 Joe Shimkus <jshimkush@redhat.com> - 1.0.2-1
- Renamed installed binary to lsb_release as a drop-in replacement for
  lsb_release.

* Tue Jul 26 2022 Joe Shimkus <jshimkush@redhat.com> - 1.0.1-1
- Make functional rpm for RHEL earlier than 9.0.
