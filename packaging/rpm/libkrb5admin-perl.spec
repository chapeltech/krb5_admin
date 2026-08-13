Name:           libkrb5admin-perl
Version:        0.5.1
Release:        1%{?dist}
Summary:        Perl Kerberos administration library and tools
License:        MIT
URL:            https://github.com/chapeltech/krb5_admin
Source0:        krb5_admin-%{version}.tar.gz

BuildRequires:  asgard-heimdal-devel
BuildRequires:  e2fsprogs-devel
BuildRequires:  gcc
BuildRequires:  libkharon-perl >= 0.8
BuildRequires:  make
BuildRequires:  perl
BuildRequires:  perl-DBD-SQLite
BuildRequires:  perl-DBI
BuildRequires:  perl-ExtUtils-MakeMaker
BuildRequires:  perl-devel
BuildRequires:  perl-generators
BuildRequires:  sqlite
BuildRequires:  swig
BuildRequires:  systemd-rpm-macros

Requires:       asgard-heimdal-libs%{?_isa}
Requires:       asgard-heimdal-clients%{?_isa}
Requires:       knc
Requires:       libkharon-perl >= 0.8
Requires:       perl-DBD-SQLite
Requires:       perl-DBI

%description
libkrb5admin-perl contains Perl modules and command-line tools for Kerberos
administration.

%package -n krb5-hostd
Summary:        Kerberos host administration daemon
BuildArch:      noarch
Requires:       %{name}%{?_isa} = %{version}-%{release}
Requires:       knc
Requires:       krb5-prestash-refresh = %{version}-%{release}
Requires:       prefork
%{?systemd_ordering}

%description -n krb5-hostd
The krb5-hostd package contains the Kerberos host administration daemon and
its socket-activated systemd services.

%package -n krb5-prestash
Summary:        Prestashed Kerberos credential utility
BuildArch:      noarch
Requires:       %{name}%{?_isa} = %{version}-%{release}

%description -n krb5-prestash
The krb5-prestash package contains the command-line utility for fetching
prestashed Kerberos credentials.

%package -n krb5-prestash-refresh
Summary:        Scheduled prestashed Kerberos credential refresh
BuildArch:      noarch
Requires:       krb5-prestash = %{version}-%{release}
%{?systemd_ordering}

%description -n krb5-prestash-refresh
The krb5-prestash-refresh package fetches prestashed Kerberos credentials at
boot and schedules regular refreshes.

%package kdc
Summary:        KDC components for libkrb5admin-perl
Requires:       %{name}%{?_isa} = %{version}-%{release}
Requires:       asgard-heimdal-kdc%{?_isa}
Requires:       prefork

%description kdc
The libkrb5admin-perl-kdc package contains KDC-side administration tools.

%prep
%autosetup -n krb5_admin-%{version}

%build
KRB5TYPE=heimdal KRB5DIR=/usr/lib/asgard \
KRB5INCDIR=/usr/include/asgard/heimdal \
KRB5LIBDIR=%{_libdir}/asgard/lib \
    perl Makefile.PL INSTALLDIRS=vendor PREFIX=%{_prefix}
(cd Krb5Admin && \
    KRB5TYPE=heimdal KRB5DIR=/usr/lib/asgard \
    KRB5INCDIR=/usr/include/asgard/heimdal \
    KRB5LIBDIR=%{_libdir}/asgard/lib \
    perl Makefile.PL INSTALLDIRS=vendor PREFIX=%{_prefix})
make -j1 V=1 VERBOSE=1

%install
export QA_RPATHS=3
make install DESTDIR=%{buildroot} INSTALLDIRS=vendor
make -C Krb5Admin install DESTDIR=%{buildroot} INSTALLDIRS=vendor
find %{buildroot} -type f \( -name .packlist -o -name perllocal.pod \) \
    -delete
if [ -d %{buildroot}%{_prefix}/man ]; then
    mkdir -p %{buildroot}%{_mandir}
    cp -a %{buildroot}%{_prefix}/man/. %{buildroot}%{_mandir}/
    rm -rf %{buildroot}%{_prefix}/man
fi

# Asgard no longer uses the Postfix notification transport.
rm -f \
    %{buildroot}%{_bindir}/krb5_setup_postfix \
    %{buildroot}%{_bindir}/prestash-notify

install -d %{buildroot}%{_unitdir} %{buildroot}%{_presetdir}
install -pm0644 systemd/*.service systemd/*.socket systemd/*.timer \
    systemd/*.target \
    %{buildroot}%{_unitdir}/
install -pm0644 systemd/*.preset %{buildroot}%{_presetdir}/
find %{buildroot} -depth -type d -empty -delete

find %{buildroot} \( -type f -o -type l \) \
    ! -path "%{buildroot}%{_mandir}/*" \
    ! -path "%{buildroot}%{_bindir}/krb5_gc_bootstrap" \
    ! -path "%{buildroot}%{_bindir}/krb5_prestash" \
    ! -path "%{buildroot}%{_sbindir}/krb5_admind" \
    ! -path "%{buildroot}%{_sbindir}/krb5_hostd" \
    ! -path "%{buildroot}%{_unitdir}/*" \
    ! -path "%{buildroot}%{_presetdir}/*" \
    | sed 's#^%{buildroot}##' > libkrb5admin-perl.files

%post
if [ ! -e /etc/services ] || \
    ! grep -Eq '^[[:space:]]*krb5_admin[[:space:]]+2666/tcp([[:space:]]|$)' /etc/services; then
    echo 'krb5_admin 2666/tcp' >> /etc/services
fi

%post -n krb5-hostd
%systemd_post krb5-hostd.target

%preun -n krb5-hostd
%systemd_preun krb5-hostd.target

%postun -n krb5-hostd
%systemd_postun_with_restart krb5-hostd.service krb5-hostd-knc.service

%post -n krb5-prestash-refresh
%systemd_post krb5-prestash-refresh.service krb5-prestash-refresh.timer

%preun -n krb5-prestash-refresh
%systemd_preun krb5-prestash-refresh.service krb5-prestash-refresh.timer

%postun -n krb5-prestash-refresh
%systemd_postun_with_restart krb5-prestash-refresh.service krb5-prestash-refresh.timer

%files -f libkrb5admin-perl.files
%license debian/copyright
%doc README
%{_mandir}/man1/krb5_admin.1*
%{_mandir}/man1/krb5_host.1*
%{_mandir}/man3/*

%files -n krb5-hostd
%license debian/copyright
%{_sbindir}/krb5_hostd
%{_mandir}/man5/krb5_hostd.conf.5*
%{_mandir}/man8/krb5_hostd.8*
%{_unitdir}/krb5-hostd.service
%{_unitdir}/krb5-hostd.socket
%{_unitdir}/krb5-hostd-knc.service
%{_unitdir}/krb5-hostd-knc.socket
%{_unitdir}/krb5-hostd.target
%{_presetdir}/80-krb5-hostd.preset

%files -n krb5-prestash
%license debian/copyright
%{_bindir}/krb5_prestash
%{_mandir}/man1/krb5_prestash.1*

%files -n krb5-prestash-refresh
%license debian/copyright
%{_unitdir}/krb5-prestash-refresh.service
%{_unitdir}/krb5-prestash-refresh.timer
%{_presetdir}/80-krb5-prestash-refresh.preset

%files kdc
%license debian/copyright
%{_bindir}/krb5_gc_bootstrap
%{_sbindir}/krb5_admind
%{_mandir}/man5/krb5_admind.conf.5*
%{_mandir}/man8/krb5_admind.8*

%changelog
* Thu Aug 13 2026 Roland C. Dowdeswell <elric@imrryr.org> - 0.5.1-1
- Support configurable cross-realm prestash sources.

* Mon Aug 10 2026 Roland C. Dowdeswell <elric@imrryr.org> - 0.5-1
- Split host services into role packages using the private Asgard Heimdal.
