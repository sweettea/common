%global modname pbit-lsb-release

%define repo_name common
%define repo_branch main

%define version 1.0.3
%define unmangled_version 1.0.3
%define release 1

Name: python3-%{modname}
Version: %{version}
Release: %{release}
Summary: python3-%{modname}
License: GPL2+
URL:     https://github.com/dm-vdo/common
Source0: %{url}/archive/refs/heads/main.tar.gz

BuildArch: noarch

Group: Development/Libraries

%if 0%{?rhel} && 0%{?rhel} < 9
BuildRequires: python39
BuildRequires: python39-devel
BuildRequires: python39-rpm-macros
BuildRequires: python39-setuptools
BuildRequires: python39-six
Requires: python39
%else
BuildRequires: python3
BuildRequires: python3-devel
BuildRequires: python3-eventlet
BuildRequires: python3-py
BuildRequires: python3-rpm-macros
BuildRequires: python3-setuptools
BuildRequires: python3-six
Requires: python3
%endif

%?python_enable_dependency_generator

%description
This package provides an lsb_release executable for platforms without one.

# AutoReq: no
# AutoProv: no
Provides: lsb_release
Conflicts: lsb_release

%prep
%autosetup -n %{repo_name}-%{repo_branch}/python/pbit_lsb_release

%build
%py3_build

%install
%py3_install

%files -n python3-%{modname}
%{_bindir}/lsb_release
%{python3_sitelib}/pbit_lsb_release/
%{python3_sitelib}/python3_pbit_lsb_release-%{version}*

%changelog
* Fri Oct 21 2022 Joe Shimkus <jshimkush@redhat.com> - 1.0.3-1
- Changed package generation per Red Hat example.

* Thu Sep 22 2022 Joe Shimkus <jshimkush@redhat.com> - 1.0.2-1
- Renamed installed binary to lsb_release as a drop-in replacement for
  lsb_release.

* Tue Jul 26 2022 Joe Shimkus <jshimkush@redhat.com> - 1.0.1-1
- Make functional rpm for RHEL earlier than 9.0.
