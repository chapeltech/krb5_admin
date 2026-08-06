Name:           libkrb5admin-perl
Version:        0.4.3
Release:        8%{?dist}
Summary:        Perl Kerberos administration library and tools
License:        MIT
URL:            https://github.com/chapeltech/krb5_admin
Source0:        krb5_admin-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  e2fsprogs-devel
BuildRequires:  heimdal-devel
BuildRequires:  libkharon-perl >= 0.8
BuildRequires:  make
BuildRequires:  perl
BuildRequires:  perl-DBD-SQLite
BuildRequires:  perl-DBI
BuildRequires:  perl-ExtUtils-MakeMaker
BuildRequires:  perl-devel
BuildRequires:  perl-generators
BuildRequires:  sqlite
BuildRequires:  systemd-rpm-macros
BuildRequires:  swig

Requires:       heimdal-libs
Requires:       heimdal-workstation
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
Requires:       %{name} = %{version}-%{release}
Requires:       krb5-prestash-refresh = %{version}-%{release}
Requires:       knc
Requires:       prefork
%{?systemd_ordering}

%description -n krb5-hostd
The krb5-hostd package contains the Kerberos host administration daemon and
its socket-activated systemd services.

%package -n krb5-prestash
Summary:        Prestashed Kerberos credential utility
BuildArch:      noarch
Requires:       %{name} = %{version}-%{release}

%description -n krb5-prestash
The krb5-prestash package contains the command-line utility for fetching
prestashed Kerberos credentials.

%package -n krb5-prestash-refresh
Summary:        Scheduled prestashed Kerberos credential refresh
BuildArch:      noarch
Requires:       krb5-prestash = %{version}-%{release}
%{?systemd_ordering}

%description -n krb5-prestash-refresh
The krb5-prestash-refresh package schedules regular refreshes of prestashed
Kerberos credentials.

%package kdc
Summary:        KDC helper for libkrb5admin-perl
Requires:       %{name} = %{version}-%{release}
Requires:       heimdal-server
Requires:       postfix
Requires:       prefork
Requires(pre):  shadow-utils

%description kdc
The libkrb5admin-perl-kdc package contains KDC-side helper tooling.

%prep
%autosetup -n krb5_admin-%{version}

%build
KRB5TYPE=heimdal KRB5DIR=/usr/lib/heimdal \
KRB5INCDIR=/usr/include/heimdal KRB5LIBDIR=%{_libdir}/heimdal/lib \
    perl Makefile.PL INSTALLDIRS=vendor PREFIX=%{_prefix}
(cd Krb5Admin && \
    KRB5TYPE=heimdal KRB5DIR=/usr/lib/heimdal \
    KRB5INCDIR=/usr/include/heimdal KRB5LIBDIR=%{_libdir}/heimdal/lib \
    perl Makefile.PL INSTALLDIRS=vendor PREFIX=%{_prefix})
make -j1 V=1 VERBOSE=1

%check
perl -Iblib/lib -Iblib/arch -IKrb5Admin/blib/lib \
    -IKrb5Admin/blib/arch -c scripts/prestash-notify

%install
export QA_RPATHS=3
make install DESTDIR=%{buildroot} INSTALLDIRS=vendor
make -C Krb5Admin install DESTDIR=%{buildroot} INSTALLDIRS=vendor
find %{buildroot} -type f \( -name .packlist -o -name perllocal.pod \) -delete
if [ -d %{buildroot}%{_prefix}/man ]; then
    mkdir -p %{buildroot}%{_mandir}
    cp -a %{buildroot}%{_prefix}/man/. %{buildroot}%{_mandir}/
    rm -rf %{buildroot}%{_prefix}/man
fi
install -d %{buildroot}%{_unitdir} %{buildroot}%{_presetdir}
install -pm0644 systemd/*.service systemd/*.socket systemd/*.timer \
    systemd/*.target \
    %{buildroot}%{_unitdir}/
install -pm0644 systemd/*.preset %{buildroot}%{_presetdir}/
find %{buildroot} -depth -type d -empty -delete
test -f %{buildroot}%{_bindir}/krb5_setup_postfix
find %{buildroot} \( -type f -o -type l \) \
    ! -path "%{buildroot}%{_mandir}/*" \
    ! -path "%{buildroot}%{_bindir}/krb5_setup_postfix" \
    ! -path "%{buildroot}%{_bindir}/prestash-notify" \
    ! -path "%{buildroot}%{_bindir}/krb5_prestash" \
    ! -path "%{buildroot}%{_sbindir}/krb5_hostd" \
    ! -path "%{buildroot}%{_unitdir}/*" \
    ! -path "%{buildroot}%{_presetdir}/*" \
    | sed 's#^%{buildroot}##' > libkrb5admin-perl.files
printf '%s\n' \
    "%{_bindir}/krb5_setup_postfix" \
    "%{_bindir}/prestash-notify" \
    > libkrb5admin-perl-kdc.files

%pre kdc
getent passwd krb5notify >/dev/null || \
    useradd --system --user-group --no-create-home krb5notify

%post -n krb5-hostd
if [ ! -e /etc/services ] || \
    ! grep -Eq '^[[:space:]]*krb5_admin[[:space:]]+2666/tcp([[:space:]]|$)' /etc/services; then
    echo 'krb5_admin 2666/tcp' >> /etc/services
fi
%systemd_post krb5-hostd.target

%preun -n krb5-hostd
%systemd_preun krb5-hostd.target

%postun -n krb5-hostd
%systemd_postun_with_restart krb5-hostd.service krb5-hostd-knc.service

%post -n krb5-prestash-refresh
%systemd_post krb5-prestash-refresh.timer

%preun -n krb5-prestash-refresh
%systemd_preun krb5-prestash-refresh.timer

%postun -n krb5-prestash-refresh
%systemd_postun_with_restart krb5-prestash-refresh.service

%files -f libkrb5admin-perl.files
%license debian/copyright
%doc README
%{_mandir}/man1/krb5_admin.1*
%{_mandir}/man1/krb5_host.1*
%{_mandir}/man3/*
%{_mandir}/man5/krb5_admind.conf.5*
%{_mandir}/man8/krb5_admind.8*

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

%files kdc -f libkrb5admin-perl-kdc.files
%license debian/copyright

%changelog
* Thu Aug 06 2026 ChapelTech <packages@chapel.tech> - 0.4.3-8
- Split the host daemon, prestash utility, and refresh policy into role packages.

* Wed Aug 05 2026 ChapelTech <packages@chapel.tech> - 0.4.3-7
- Build against EPEL Heimdal and correct client runtime dependencies.
- Skip certificate prestashing because EPEL Heimdal lacks kx509 support.

* Wed Aug 05 2026 ChapelTech <packages@chapel.tech> - 0.4.3-6
- Fix the prestash notification worker on Debian and Rocky.

* Wed Aug 05 2026 ChapelTech <packages@chapel.tech> - 0.4.3-5
- Use the standard host keytab path for client authentication.

* Wed Aug 05 2026 ChapelTech <packages@chapel.tech> - 0.4.3-4
- Package the canonical host daemon units and prestash timer.

* Wed Aug 05 2026 ChapelTech <packages@chapel.tech> - 0.4.3-3
- Enable the client sockets through the system preset policy.

* Wed Aug 05 2026 ChapelTech <packages@chapel.tech> - 0.4.3-2
- Add socket-activated prefork services for KNC and krb5_hostd.

* Thu Apr 30 2026 Codex <codex@example.invalid> - 0.4.3-1
- Build RHEL 9 packages from upstream Debian packaging metadata.
