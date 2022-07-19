%define repo_name common
%define repo_branch main

%define name python3-pbit-lsb-release
%define version 1.0.0
%define unmangled_version 1.0.0
%define release 1

Summary: %{name}
Name: %{name}
Version: %{version}
Release: %{release}
URL: https://gitlab.cee.redhat.com/vdo/open-sourcing/src/%{repo_name}
Source0: %{url}/-/archive/%{repo_branch}/%{repo_name}-%{repo_branch}.tar.gz
License: GPL2+
Group: Development/Libraries
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Prefix: %{_prefix}
BuildArch: noarch

# Build dependencies
BuildRequires: python3
BuildRequires: python-setuptools

# Runtime dependencies
# Requires:

%description
UNKNOWN

%prep
%setup -n %{repo_name}-%{repo_branch}

%build
python3 setup.py build

%install
python3 setup.py install --single-version-externally-managed -O1 --root=$RPM_BUILD_ROOT --record=INSTALLED_FILES

%clean
rm -rf $RPM_BUILD_ROOT

%files -f INSTALLED_FILES
%defattr(-,root,root)
