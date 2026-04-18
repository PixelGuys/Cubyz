const std = @import("../../std.zig");
const assert = std.debug.assert;
const windows = std.os.windows;

const USHORT = windows.USHORT;
const LONG = windows.LONG;

pub const GROUP = u32;
pub const ADDRESS_FAMILY = u16;

// Microsoft use the signed c_int for this, but it should never be negative
pub const socklen_t = u32;

pub const TCP = struct {
    pub const NODELAY = 1;
    pub const EXPEDITED_1122 = 2;
    pub const OFFLOAD_NO_PREFERENCE = 0;
    pub const OFFLOAD_NOT_PREFERRED = 1;
    pub const OFFLOAD_PREFERRED = 2;
    pub const KEEPALIVE = 3;
    pub const MAXSEG = 4;
    pub const MAXRT = 5;
    pub const STDURG = 6;
    pub const NOURG = 7;
    pub const ATMARK = 8;
    pub const NOSYNRETRIES = 9;
    pub const TIMESTAMPS = 10;
    pub const OFFLOAD_PREFERENCE = 11;
    pub const CONGESTION_ALGORITHM = 12;
    pub const DELAY_FIN_ACK = 13;
    pub const MAXRTMS = 14;
    pub const FASTOPEN = 15;
    pub const KEEPCNT = 16;
    pub const KEEPINTVL = 17;
    pub const FAIL_CONNECT_ON_ICMP_ERROR = 18;
    pub const ICMP_ERROR_INFO = 19;
    pub const BSDURGENT = 28672;
};

pub const AF = struct {
    pub const UNSPEC = 0;
    pub const UNIX = 1;
    pub const INET = 2;
    pub const IMPLINK = 3;
    pub const PUP = 4;
    pub const CHAOS = 5;
    pub const NS = 6;
    pub const IPX = 6;
    pub const ISO = 7;
    pub const ECMA = 8;
    pub const DATAKIT = 9;
    pub const CCITT = 10;
    pub const SNA = 11;
    pub const DECnet = 12;
    pub const DLI = 13;
    pub const LAT = 14;
    pub const HYLINK = 15;
    pub const APPLETALK = 16;
    pub const NETBIOS = 17;
    pub const VOICEVIEW = 18;
    pub const FIREFOX = 19;
    pub const UNKNOWN1 = 20;
    pub const BAN = 21;
    pub const ATM = 22;
    pub const INET6 = 23;
    pub const CLUSTER = 24;
    pub const @"12844" = 25;
    pub const IRDA = 26;
    pub const NETDES = 28;
    pub const MAX = 29;
    pub const TCNPROCESS = 29;
    pub const TCNMESSAGE = 30;
    pub const ICLFXBM = 31;
    pub const BTH = 32;
    pub const LINK = 33;
    pub const HYPERV = 34;
};

pub const SOCK = struct {
    pub const STREAM = 1;
    pub const DGRAM = 2;
    pub const RAW = 3;
    pub const RDM = 4;
    pub const SEQPACKET = 5;
};

pub const SOL = struct {
    pub const IRLMP = 255;
    pub const SOCKET = 65535;
};

pub const SO = struct {
    pub const DEBUG = 1;
    pub const ACCEPTCONN = 2;
    pub const REUSEADDR = 4;
    pub const KEEPALIVE = 8;
    pub const DONTROUTE = 16;
    pub const BROADCAST = 32;
    pub const USELOOPBACK = 64;
    pub const LINGER = 128;
    pub const OOBINLINE = 256;
    pub const SNDBUF = 4097;
    pub const RCVBUF = 4098;
    pub const SNDLOWAT = 4099;
    pub const RCVLOWAT = 4100;
    pub const SNDTIMEO = 4101;
    pub const RCVTIMEO = 4102;
    pub const ERROR = 4103;
    pub const TYPE = 4104;
    pub const BSP_STATE = 4105;
    pub const GROUP_ID = 8193;
    pub const GROUP_PRIORITY = 8194;
    pub const MAX_MSG_SIZE = 8195;
    pub const CONDITIONAL_ACCEPT = 12290;
    pub const PAUSE_ACCEPT = 12291;
    pub const COMPARTMENT_ID = 12292;
    pub const RANDOMIZE_PORT = 12293;
    pub const PORT_SCALABILITY = 12294;
    pub const REUSE_UNICASTPORT = 12295;
    pub const REUSE_MULTICASTPORT = 12296;
    pub const ORIGINAL_DST = 12303;
    pub const PROTOCOL_INFOA = 8196;
    pub const PROTOCOL_INFOW = 8197;
    pub const CONNDATA = 28672;
    pub const CONNOPT = 28673;
    pub const DISCDATA = 28674;
    pub const DISCOPT = 28675;
    pub const CONNDATALEN = 28676;
    pub const CONNOPTLEN = 28677;
    pub const DISCDATALEN = 28678;
    pub const DISCOPTLEN = 28679;
    pub const OPENTYPE = 28680;
    pub const SYNCHRONOUS_ALERT = 16;
    pub const SYNCHRONOUS_NONALERT = 32;
    pub const MAXDG = 28681;
    pub const MAXPATHDG = 28682;
    pub const UPDATE_ACCEPT_CONTEXT = 28683;
    pub const CONNECT_TIME = 28684;
    pub const UPDATE_CONNECT_CONTEXT = 28688;

    pub const UNIX_PATH = 0x98000000;
};

pub const MSG = struct {
    pub const OOB = 0x1;
    pub const PEEK = 0x2;
    pub const DONTROUTE = 0x4;
    pub const WAITALL = 0x8;
    pub const INTERRUPT = 0x10;
    pub const PUSH_IMMEDIATE = 0x20;

    pub const TRUNC = 0x0100;
    pub const CTRUNC = 0x0200;
    pub const BCAST = 0x0400;
    pub const MCAST = 0x0800;

    pub const PARTIAL = 0x8000;

    pub const MAXIOVLEN = 16;
};

pub const IPPROTO = struct {
    pub const IP = 0;
    pub const ICMP = 1;
    pub const IGMP = 2;
    pub const GGP = 3;
    pub const TCP = 6;
    pub const PUP = 12;
    pub const UDP = 17;
    pub const IDP = 22;
    pub const ND = 77;
    pub const RM = 113;
    pub const RAW = 255;
    pub const MAX = 256;
};

pub const FLOWSPEC = extern struct {
    TokenRate: u32,
    TokenBucketSize: u32,
    PeakBandwidth: u32,
    Latency: u32,
    DelayVariation: u32,
    ServiceType: u32,
    MaxSduSize: u32,
    MinimumPolicedSize: u32,
};

pub const sockproto = extern struct {
    sp_family: u16,
    sp_protocol: u16,
};

pub const linger = extern struct {
    onoff: u16,
    linger: u16,
};

pub const sockaddr = extern struct {
    family: ADDRESS_FAMILY,
    data: [14]u8,

    pub const SS_MAXSIZE = 128;
    pub const storage = extern struct {
        family: ADDRESS_FAMILY align(8),
        padding: [SS_MAXSIZE - @sizeOf(ADDRESS_FAMILY)]u8 = undefined,

        comptime {
            assert(@sizeOf(storage) == SS_MAXSIZE);
            assert(@alignOf(storage) == 8);
        }
    };

    /// IPv4 socket address
    pub const in = extern struct {
        family: ADDRESS_FAMILY = AF.INET,
        port: USHORT,
        addr: u32,
        zero: [8]u8 = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
    };

    /// IPv6 socket address
    pub const in6 = extern struct {
        family: ADDRESS_FAMILY = AF.INET6,
        port: USHORT,
        flowinfo: u32,
        addr: [16]u8,
        scope_id: u32,
    };

    /// UNIX domain socket address
    pub const un = extern struct {
        family: ADDRESS_FAMILY = AF.UNIX,
        path: [108]u8,
    };
};

pub const hostent = extern struct {
    h_name: [*]u8,
    h_aliases: **i8,
    h_addrtype: i16,
    h_length: i16,
    h_addr_list: **i8,
};

pub const timeval = extern struct {
    sec: LONG,
    usec: LONG,
};
