%global snapshot 20260804.fa92377c
%global private_root %{_prefix}/lib/asgard
%global private_libdir %{_libdir}/asgard/lib
%global private_datadir %{_datadir}/asgard/heimdal
%global private_includedir %{_includedir}/asgard/heimdal
%global debug_package %{nil}
%global _build_id_links none

Name:           asgard-heimdal
Version:        7.99.1
Release:        0.1.%{snapshot}%{?dist}
Summary:        Private Heimdal Kerberos implementation for Asgard
License:        BSD and MIT
URL:            https://github.com/heimdal/heimdal
Source0:        %{name}-%{version}-%{snapshot}.tar.gz

ExclusiveArch:  x86_64

BuildRequires:  autoconf
BuildRequires:  automake
BuildRequires:  binutils
BuildRequires:  bison
BuildRequires:  file
BuildRequires:  flex
BuildRequires:  gcc
BuildRequires:  gettext-devel
BuildRequires:  libcap-ng-devel
BuildRequires:  libdb-devel
BuildRequires:  libtool
BuildRequires:  make
BuildRequires:  openssl-devel
BuildRequires:  perl-interpreter
BuildRequires:  perl-JSON
BuildRequires:  pkgconfig
BuildRequires:  python3
BuildRequires:  readline-devel
BuildRequires:  sqlite-devel
BuildRequires:  zlib-devel

%description
This source package builds a private Heimdal Kerberos implementation for
Asgard. It intentionally does not provide a main binary package or replace
the operating system Kerberos implementation.

%package libs
Summary:        Private Heimdal runtime libraries for Asgard

%description libs
The asgard-heimdal-libs package contains Heimdal shared libraries installed
in an Asgard-private runtime directory.

%package clients
Summary:        Private Heimdal client tools for Asgard
Requires:       %{name}-libs%{?_isa} = %{version}-%{release}

%description clients
The asgard-heimdal-clients package contains Heimdal client tools installed
under /usr/lib/asgard. Only kx509 is exposed on the public command path.

%package kdc
Summary:        Private Heimdal KDC tools and daemons for Asgard
Requires:       %{name}-libs%{?_isa} = %{version}-%{release}

%description kdc
The asgard-heimdal-kdc package contains private Heimdal KDC administration
tools and daemons. It does not install Kerberos configuration or service
policy.

%package devel
Summary:        Development files for the private Asgard Heimdal libraries
Requires:       %{name}-libs%{?_isa} = %{version}-%{release}

%description devel
The asgard-heimdal-devel package contains headers, unversioned shared-library
links, pkg-config metadata, and private code-generation tools.

%prep
%autosetup -n %{name}-%{version}-%{snapshot}

%build
./autogen.sh
%configure \
    --disable-heimdal-documentation \
    --disable-static \
    --enable-kx509 \
    --enable-pk-init \
    --enable-shared \
    --with-berkeley-db \
    --with-capng \
    --with-hdbdir=%{_localstatedir}/lib/asgard/heimdal \
    --with-microhttpd=no \
    --with-openldap=no \
    --with-sqlite3=/usr \
    --bindir=%{private_root}/bin \
    --sbindir=%{private_root}/sbin \
    --libexecdir=%{private_root}/libexec \
    --libdir=%{private_libdir} \
    --includedir=%{private_includedir} \
    --datarootdir=%{private_datadir} \
    --mandir=%{private_datadir}/man \
    --infodir=%{private_datadir}/info \
    --sysconfdir=%{_sysconfdir} \
    --localstatedir=%{_localstatedir}/lib/asgard/heimdal \
    --runstatedir=%{_rundir}/asgard/heimdal \
    LDFLAGS="%{build_ldflags} -Wl,--enable-new-dtags -Wl,-rpath,%{private_libdir}"
%make_build

%install
export QA_RPATHS=3
%make_install

# Static archives and libtool metadata are not part of the private ABI.
find %{buildroot}%{private_libdir} -type f \( -name '*.a' -o -name '*.la' \) -delete

rm -f \
    %{buildroot}%{private_root}/bin/kadmin \
    %{buildroot}%{private_root}/bin/ktutil \
    %{buildroot}%{private_datadir}/man/man1/kadmin.1 \
    %{buildroot}%{private_datadir}/man/man1/ktutil.1

# These upstream validation binaries and modules are installed despite being
# test-only.
find \
    %{buildroot}%{private_root} \
    %{buildroot}%{private_libdir} \
    \( -name 'test_*' -o -name 'kdc_test_plugin*' \) -delete
find %{buildroot} -depth -type d -empty -delete

install -d %{buildroot}%{_bindir}
ln -s ../lib/asgard/bin/heimtools %{buildroot}%{_bindir}/kx509

# Refuse any install outside the private trees and the one public command.
find %{buildroot} -mindepth 1 \( -type f -o -type l \) -print | sort | \
while IFS= read -r path; do
    installed=${path#%{buildroot}}
    case "$installed" in
        %{_bindir}/kx509|\
        %{private_root}/*|\
        %{private_libdir}/*|\
        %{private_includedir}/*|\
        %{private_datadir}/*) ;;
        *)
            echo "unexpected non-private install path: $installed" >&2
            exit 1
            ;;
    esac
done

# Any ELF object using a bundled SONAME must carry a RUNPATH to the private
# library directory. RPATH is deliberately rejected.
find %{buildroot}%{private_libdir} -type f -name '*.so.*' -print | sort | \
while IFS= read -r library; do
    readelf -d "$library" 2>/dev/null | \
        sed -n 's/.*(SONAME).*\[\(.*\)\].*/\1/p'
done > private-sonames

find %{buildroot}%{private_root} %{buildroot}%{private_libdir} \
    -type f -print | sort | \
while IFS= read -r object; do
    dynamic=$(mktemp)
    if ! readelf -d "$object" >"$dynamic" 2>/dev/null; then
        rm -f "$dynamic"
        continue
    fi
    needs_private=false
    while IFS= read -r soname; do
        if grep -Fq "Shared library: [$soname]" "$dynamic"; then
            needs_private=true
            break
        fi
    done < private-sonames
    if test "$needs_private" = true; then
        if grep -q '(RPATH)' "$dynamic" || \
           ! grep -Eq '\(RUNPATH\).*\[%{private_libdir}(:[^]]*)?\]' "$dynamic"; then
            echo "$object does not use the private library RUNPATH" >&2
            cat "$dynamic" >&2
            rm -f "$dynamic"
            exit 1
        fi
    fi
    rm -f "$dynamic"
done

: > asgard-heimdal-libs.files
: > asgard-heimdal-clients.files
: > asgard-heimdal-kdc.files
: > asgard-heimdal-devel.files

find %{buildroot} -mindepth 1 -print | sort | \
while IFS= read -r path; do
    installed=${path#%{buildroot}}

    case "$installed" in
        %{_prefix}|%{_bindir}|%{_prefix}/lib|%{_libdir}|\
        %{_includedir}|%{_datadir})
            continue ;;
    esac

    if test -d "$path"; then
        case "$installed" in
            %{private_libdir}|%{_libdir}/asgard)
                list=asgard-heimdal-libs.files ;;
            %{private_includedir}|%{private_includedir}/*|%{_includedir}/asgard)
                list=asgard-heimdal-devel.files ;;
            %{private_root}/sbin)
                list=asgard-heimdal-kdc.files ;;
            *)
                list=asgard-heimdal-clients.files ;;
        esac
        printf '%s %s\n' '%%dir' "$installed" >> "$list"
        continue
    fi

    case "$installed" in
        %{private_libdir}/ipc_csr_authorizer.so)
            list=asgard-heimdal-kdc.files ;;
        %{private_libdir}/*.so)
            list=asgard-heimdal-devel.files ;;
        %{private_libdir}/*.so.*)
            list=asgard-heimdal-libs.files ;;
        %{private_libdir}/pkgconfig/*)
            list=asgard-heimdal-devel.files ;;
        %{private_includedir}/*)
            list=asgard-heimdal-devel.files ;;
        %{private_root}/bin/asn1_compile|\
        %{private_root}/bin/asn1_print|\
        %{private_root}/bin/krb5-config|\
        %{private_root}/libexec/heimdal/slc)
            list=asgard-heimdal-devel.files ;;
        %{private_root}/bin/string2key|\
        %{private_root}/sbin/*|\
        %{private_root}/libexec/bx509d|\
        %{private_root}/libexec/hprop|\
        %{private_root}/libexec/hpropd|\
        %{private_root}/libexec/httpkadmind|\
        %{private_root}/libexec/ipropd-master|\
        %{private_root}/libexec/ipropd-slave|\
        %{private_root}/libexec/kadmind|\
        %{private_root}/libexec/kdc|\
        %{private_root}/libexec/kpasswdd)
            list=asgard-heimdal-kdc.files ;;
        %{private_datadir}/man/man3/*|\
        %{private_datadir}/man/man1/asn1_compile.1*|\
        %{private_datadir}/man/man1/asn1_print.1*|\
        %{private_datadir}/man/man1/krb5-config.1*)
            list=asgard-heimdal-devel.files ;;
        %{private_datadir}/man/man8/bx509d.8*|\
        %{private_datadir}/man/man8/hprop.8*|\
        %{private_datadir}/man/man8/hpropd.8*|\
        %{private_datadir}/man/man8/httpkadmind.8*|\
        %{private_datadir}/man/man8/iprop-log.8*|\
        %{private_datadir}/man/man8/iprop.8*|\
        %{private_datadir}/man/man8/ipropd-master.8*|\
        %{private_datadir}/man/man8/ipropd-slave.8*|\
        %{private_datadir}/man/man8/kadmind.8*|\
        %{private_datadir}/man/man8/kdc.8*|\
        %{private_datadir}/man/man8/kpasswdd.8*|\
        %{private_datadir}/man/man8/kstash.8*|\
        %{private_datadir}/man/man8/string2key.8*)
            list=asgard-heimdal-kdc.files ;;
        *)
            list=asgard-heimdal-clients.files ;;
    esac
    printf '%s\n' "$installed" >> "$list"
done

%files libs -f asgard-heimdal-libs.files
%license LICENSE

%files clients -f asgard-heimdal-clients.files
%license LICENSE

%files kdc -f asgard-heimdal-kdc.files
%license LICENSE

%files devel -f asgard-heimdal-devel.files
%license LICENSE

%changelog
* Thu Aug 06 2026 ChapelTech <packages@chapel.tech> - 7.99.1-0.1.20260804.fa92377c
- Package the pinned Heimdal snapshot in an Asgard-private filesystem layout.
