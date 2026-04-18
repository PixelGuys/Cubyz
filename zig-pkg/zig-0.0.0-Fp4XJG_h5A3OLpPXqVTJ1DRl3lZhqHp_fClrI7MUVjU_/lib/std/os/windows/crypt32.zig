const std = @import("../../std.zig");
const windows = std.os.windows;

const BOOL = windows.BOOL;
const DWORD = windows.DWORD;
const BYTE = windows.BYTE;
const LONG = windows.LONG;
const LPCSTR = windows.LPCSTR;
const LPCWSTR = windows.LPCWSTR;
const FILETIME = windows.FILETIME;
const HANDLE = windows.HANDLE;

// ref: um/wincrypt.h

pub const HCRYPTPROV_LEGACY = enum(usize) { NULL = 0 };

pub const CERT_INFO = *opaque {};

pub const CTL_USAGE = extern struct {
    cUsageIdentifier: DWORD,
    rgpszUsageIdentifier: [*]const LPCSTR,
};

pub const CERT_ENHKEY_USAGE = CTL_USAGE;

pub const ENCODING = enum(u16) {
    UNSPECIFIED = 0x0000,
    ASN = 0x0001,
    NDR = 0x0002,
    _,

    pub const TYPE = packed struct(DWORD) {
        CERT: ENCODING = .UNSPECIFIED,
        CMSG: ENCODING = .UNSPECIFIED,
    };
};

pub const HCERTSTORE = *opaque {};

pub const CERT_CONTEXT = extern struct {
    dwCertEncodingType: ENCODING.TYPE,
    pbCertEncoded: [*]BYTE,
    cbCertEncoded: DWORD,
    pCertInfo: CERT_INFO,
    hCertStore: HCERTSTORE,
};

pub const CERT_STORE = struct {
    pub const PROV = enum(usize) {
        MSG = 1,
        MEMORY = 2,
        FILE = 3,
        REG = 4,

        PKCS7 = 5,
        SERIALIZED = 6,
        FILENAME_A = 7,
        FILENAME_W = 8,
        SYSTEM_A = 9,
        SYSTEM_W = 10,

        COLLECTION = 11,
        SYSTEM_REGISTRY_A = 12,
        SYSTEM_REGISTRY_W = 13,
        PHYSICAL_W = 14,

        SMART_CARD_W = 15,

        LDAP_W = 16,
        PKCS12 = 17,

        /// LPCSTR
        _,

        pub fn fromString(str: LPCSTR) PROV {
            return @enumFromInt(@intFromPtr(str));
        }
    };

    pub const FLAG = packed struct(DWORD) {
        NO_CRYPT_RELEASE: bool = false,
        SET_LOCALIZED_NAME: bool = false,
        DEFER_CLOSE_UNTIL_LAST_FREE: bool = false,
        Reserved3: u1 = 0,
        DELETE: bool = false,
        UNSAFE_PHYSICAL: bool = false,
        SHARE_STORE: bool = false,
        SHARE_CONTEXT: bool = false,
        MANIFOLD: bool = false,
        ENUM_ARCHIVED: bool = false,
        UPDATE_KEYID: bool = false,
        BACKUP_RESTORE: bool = false,
        MAXIMUM_ALLOWED: bool = false,
        CREATE_NEW: bool = false,
        OPEN_EXISTING: bool = false,
        READONLY: bool = false,
        Reserved16: u16 = 0,
    };

    pub const ADD = enum(DWORD) {
        NEW = 1,
        USE_EXISTING = 2,
        REPLACE_EXISTING = 3,
        ALWAYS = 4,
        REPLACE_EXISTING_INHERIT_PROPERTIES = 5,
        REWER = 6,
        NEWER_INHERIT_PROPERTIES = 7,
        _,
    };
};

pub extern "crypt32" fn CertOpenStore(
    lpszStoreProvider: CERT_STORE.PROV,
    dwEncodingType: ENCODING.TYPE,
    hCryptProv: HCRYPTPROV_LEGACY,
    dwFlags: CERT_STORE.FLAG,
    pvPara: ?*const anyopaque,
) callconv(.winapi) ?HCERTSTORE;

pub const CERT_CLOSE_STORE_FLAG = packed struct(DWORD) {
    FORCE: bool = false,
    CHECK: bool = false,
    Reserved2: u30 = 0,
};

pub extern "crypt32" fn CertCloseStore(
    hCertStore: HCERTSTORE,
    dwFlags: CERT_CLOSE_STORE_FLAG,
) callconv(.winapi) BOOL;

pub extern "crypt32" fn CertEnumCertificatesInStore(
    hCertStore: HCERTSTORE,
    pPrevCertContext: ?*CERT_CONTEXT,
) callconv(.winapi) ?*CERT_CONTEXT;

pub extern "crypt32" fn CertFreeCertificateContext(
    pCertContext: ?*const CERT_CONTEXT,
) callconv(.winapi) BOOL;

pub extern "crypt32" fn CertAddEncodedCertificateToStore(
    hCertStore: ?HCERTSTORE,
    dwCertEncodingType: ENCODING.TYPE,
    pbCertEncoded: [*]const BYTE,
    cbCertEncoded: DWORD,
    dwAddDisposition: CERT_STORE.ADD,
    ppCertContext: ?*?*const CERT_CONTEXT,
) callconv(.winapi) BOOL;

pub extern "crypt32" fn CertOpenSystemStoreW(
    hProv: HCRYPTPROV_LEGACY,
    szSubsystemProtocol: LPCWSTR,
) callconv(.winapi) ?HCERTSTORE;

pub const HCERTCHAINENGINE = enum(usize) {
    CURRENT_USER = 0x0,
    LOCAL_MACHINE = 0x1,
    SERIAL_LOCAL_MACHINE = 0x2,
    /// HANDLE
    _,

    pub fn fromHandle(handle: HANDLE) HCERTCHAINENGINE {
        return @enumFromInt(@intFromPtr(handle));
    }
};

pub const CERT_CHAIN = packed struct(DWORD) {
    CACHE_END_CERT: bool = false,
    THREAD_STORE_SYNC: bool = false,
    CACHE_ONLY_URL_RETRIEVAL: bool = false,
    USE_LOCAL_MACHINE_STORE: bool = false,
    ENABLE_CACHE_AUTO_UPDATE: bool = false,
    ENABLE_SHARE_STORE: bool = false,
    Reserved6: u20 = 0,
    REVOCATION_CHECK_OCSP_CERT: bool = false,
    REVOCATION_ACCUMULATIVE_TIMEOUT: bool = false,
    REVOCATION_CHECK_END_CERT: bool = false,
    REVOCATION_CHECK_CHAIN: bool = false,
    REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT: bool = false,
    REVOCATION_CHECK_CACHE_ONLY: bool = false,

    pub const CONTEXT = opaque {};

    pub const USAGE_MATCH = extern struct {
        dwType: TYPE,
        Usage: CERT_ENHKEY_USAGE,

        pub const TYPE = enum(DWORD) { AND = 0x00000000, OR = 0x00000001, _ };
    };

    pub const PARA = extern struct {
        cbSize: DWORD = @sizeOf(PARA),
        RequestedUsage: USAGE_MATCH,
    };

    pub const POLICY = enum(usize) {
        BASE = 1,
        AUTHENTICODE = 2,
        AUTHENTICODE_TS = 3,
        SSL = 4,
        BASIC_CONSTRAINTS = 5,
        NT_AUTH = 6,
        MICROSOFT_ROOT = 7,
        EV = 8,
        SSL_F12 = 9,
        SSL_HPKP_HEADER = 10,
        THIRD_PARTY_ROOT = 11,
        SSL_KEY_PIN = 12,
        CT = 13,
        /// LPCSTR
        _,

        pub fn fromString(str: LPCSTR) POLICY {
            return @enumFromInt(@intFromPtr(str));
        }

        pub const PARA = extern struct {
            cbSize: DWORD = @sizeOf(POLICY.PARA),
            dwFlags: FLAG,
            pvExtraPolicyPara: ?*anyopaque,
        };

        pub const STATUS = extern struct {
            cbSize: DWORD = @sizeOf(STATUS),
            dwError: windows.Win32Error,
            lChainIndex: LONG,
            lElementIndex: LONG,
            pvExtraPolicyStatus: ?*anyopaque,
        };

        pub const FLAG = packed struct(DWORD) {
            IGNORE_NOT_TIME_VALID: bool = false,
            IGNORE_CTL_NOT_TIME_VALID: bool = false,
            IGNORE_NOT_TIME_NESTED: bool = false,
            IGNORE_INVALID_BASIC_CONSTRAINTS: bool = false,
            ALLOW_UNKNOWN_CA: bool = false,
            IGNORE_WRONG_USAGE: bool = false,
            IGNORE_INVALID_NAME: bool = false,
            IGNORE_INVALID_POLICY: bool = false,
            IGNORE_END_REV_UNKNOWN: bool = false,
            IGNORE_CTL_SIGNER_REV_UNKNOWN: bool = false,
            IGNORE_CA_REV_UNKNOWN: bool = false,
            IGNORE_ROOT_REV_UNKNOWN: bool = false,
            IGNORE_PEER_TRUST: bool = false,
            IGNORE_NOT_SUPPORTED_CRITICAL_EXT: bool = false,
            TRUST_TESTROOT: bool = false,
            ALLOW_TESTROOT: bool = false,
            Reserved16: u11 = 0,
            IGNORE_WEAK_SIGNATURE: bool = false,
            Reserved28: u4 = 0,
        };
    };
};

pub const HTTPSPolicyCallbackData = extern struct {
    cbSize: DWORD = @sizeOf(HTTPSPolicyCallbackData),
    dwAuthType: AUTHTYPE,
    fdwChecks: DWORD = 0,
    pwszServerName: ?LPCWSTR = null,

    pub const AUTHTYPE = enum(DWORD) { CLIENT = 1, SERVER = 2, _ };
};

pub extern "crypt32" fn CertGetCertificateChain(
    hChainEngine: HCERTCHAINENGINE,
    pCertContext: *const CERT_CONTEXT,
    pTime: ?*const FILETIME,
    hAdditionalStore: ?HCERTSTORE,
    pChainPara: *const CERT_CHAIN.PARA,
    dwFlags: CERT_CHAIN,
    pvReserved: ?*const anyopaque,
    ppChainContext: **const CERT_CHAIN.CONTEXT,
) callconv(.winapi) BOOL;

pub extern "crypt32" fn CertFreeCertificateChain(
    pChainContext: *const CERT_CHAIN.CONTEXT,
) callconv(.winapi) void;

pub extern "crypt32" fn CertVerifyCertificateChainPolicy(
    pszPolicyOID: CERT_CHAIN.POLICY,
    pChainContext: *const CERT_CHAIN.CONTEXT,
    pPolicyPara: *const CERT_CHAIN.POLICY.PARA,
    pPolicyStatus: *CERT_CHAIN.POLICY.STATUS,
) callconv(.winapi) BOOL;
