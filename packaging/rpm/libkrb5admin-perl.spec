Name:           libkrb5admin-perl
Version:        0.4.3
Release:        6%{?dist}
Summary:        Perl Kerberos administration library and tools
License:        MIT
URL:            https://github.com/elric1/krb5_admin
Source0:        krb5_admin-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  e2fsprogs-devel
BuildRequires:  heimdal
BuildRequires:  knc
BuildRequires:  libkharon-perl >= 0.8
BuildRequires:  make
BuildRequires:  patchelf
BuildRequires:  perl
BuildRequires:  perl-DBD-SQLite
BuildRequires:  perl-DBI
BuildRequires:  perl-ExtUtils-MakeMaker
BuildRequires:  perl-devel
BuildRequires:  perl-generators
BuildRequires:  sqlite
BuildRequires:  systemd-rpm-macros
BuildRequires:  swig

Requires:       heimdal
Requires:       knc
Requires:       libkharon-perl >= 0.8
Requires:       perl-DBD-SQLite
Requires:       perl-DBI
Requires:       prefork
%{?systemd_ordering}

%description
libkrb5admin-perl contains Perl modules and command-line tools for Kerberos
administration.

%package kdc
Summary:        KDC helper for libkrb5admin-perl
Requires:       %{name} = %{version}-%{release}
Requires:       postfix

%description kdc
The libkrb5admin-perl-kdc package contains KDC-side helper tooling.

%prep
%autosetup -n krb5_admin-%{version}
sed -i 's#-L${KRB5DIR}/lib -Wl,-R${KRB5DIR}/lib#-L${KRB5DIR}/lib64 -Wl,-rpath,${KRB5DIR}/lib64#' Krb5Admin/Makefile.PL

%build
KRB5TYPE=heimdal KRB5DIR=/opt/heimdal perl Makefile.PL INSTALLDIRS=vendor PREFIX=%{_prefix}
make -j1 V=1 VERBOSE=1

%check
perl -Iblib/lib -Iblib/arch -c scripts/prestash-notify

%install
KRB5TYPE=heimdal KRB5DIR=/opt/heimdal make install DESTDIR=%{buildroot} INSTALLDIRS=vendor
find %{buildroot} -type f \( -name .packlist -o -name perllocal.pod \) -delete
if [ -d %{buildroot}%{_prefix}/man ]; then
    mkdir -p %{buildroot}%{_mandir}
    cp -a %{buildroot}%{_prefix}/man/. %{buildroot}%{_mandir}/
    rm -rf %{buildroot}%{_prefix}/man
fi
install -d %{buildroot}%{_unitdir} %{buildroot}%{_presetdir}
install -pm0644 systemd/*.service systemd/*.socket systemd/*.timer \
    %{buildroot}%{_unitdir}/
install -pm0644 systemd/80-krb5-admin.preset \
    %{buildroot}%{_presetdir}/80-krb5-admin.preset
find %{buildroot} -type f -print0 | while IFS= read -r -d '' file; do
    if file "$file" | grep -q 'ELF'; then
        patchelf --remove-rpath "$file" 2>/dev/null || true
    fi
done
find %{buildroot} -depth -type d -empty -delete
test -f %{buildroot}%{_bindir}/krb5_setup_postfix
find %{buildroot} \( -type f -o -type l \) \
    ! -path "%{buildroot}%{_mandir}/*" \
    ! -path "%{buildroot}%{_bindir}/krb5_setup_postfix" \
    | sed 's#^%{buildroot}##' > libkrb5admin-perl.files
echo "%{_bindir}/krb5_setup_postfix" > libkrb5admin-perl-kdc.files

%pre kdc
getent passwd krb5notify >/dev/null || \
    useradd --system --user-group --no-create-home krb5notify

%post
if ! grep -Eq '^[[:space:]]*krb5_admin[[:space:]]+2666/tcp([[:space:]]|$)' /etc/services; then
    echo 'krb5_admin 2666/tcp' >> /etc/services
fi
%systemd_post krb5-hostd.socket krb5-hostd-knc.socket krb5-prestash.timer

%preun
%systemd_preun krb5-hostd.socket krb5-hostd-knc.socket krb5-prestash.timer

%postun
%systemd_postun_with_restart krb5-hostd.service krb5-hostd-knc.service krb5-prestash.service

%files -f libkrb5admin-perl.files
%license debian/copyright
%doc README
%{_mandir}/man*/*

%files kdc -f libkrb5admin-perl-kdc.files
%license debian/copyright

%changelog
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
