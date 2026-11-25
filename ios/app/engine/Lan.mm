#import "Bridge.h"
#include <arpa/inet.h>
#include <atomic>
#include <cstring>
#include <fcntl.h>
#include <mutex>
#include <netdb.h>
#include <poll.h>
#include <string>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>
#include <vector>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509v3.h>

namespace {
std::string ssl_error(const char *what)
{
    char buf[200] = "";
    if (unsigned long e = ERR_get_error()) ERR_error_string_n(e, buf, sizeof(buf));
    ERR_clear_error();
    return std::string(what) + (buf[0] ? std::string(": ") + buf : "");
}

// One TLS connection. Reads run on one thread, writes are serialized by a mutex.
class Tls
{
public:
    ~Tls() { close(); }
    // The printer's certificate is signed by the vendor CA shipped in resources/cert and carries the serial as CN.
    std::string connect(const std::string &host, int port, const std::string &serial, const std::string &ca, SSL_SESSION *session = nullptr, int timeout_ms = 8000)
    {
        std::string err = tcp(host, port, timeout_ms);
        if (!err.empty()) return err;
        ctx = SSL_CTX_new(TLS_client_method());
        if (!ctx) return ssl_error("TLS");
        if (SSL_CTX_load_verify_locations(ctx, ca.c_str(), nullptr) != 1) return ssl_error("cannot load the printer CA");
        SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, nullptr);
        SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
        ssl = SSL_new(ctx);
        SSL_set_tlsext_host_name(ssl, serial.c_str());
        SSL_set_fd(ssl, fd);
        if (session) SSL_set_session(ssl, session);
        if (SSL_connect(ssl) != 1) return ssl_error("secure connection refused (wrong serial number or untrusted certificate?)");
        X509 *cert = SSL_get1_peer_certificate(ssl);
        char  cn[128] = "";
        if (cert) { X509_NAME_get_text_by_NID(X509_get_subject_name(cert), NID_commonName, cn, sizeof(cn)); X509_free(cert); }
        if (serial != cn) return "the printer's certificate does not match the serial number";
        struct timeval tv = {30, 0};
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        return "";
    }
    bool write(const void *data, size_t n)
    {
        std::lock_guard<std::mutex> l(mtx);
        const char *q = (const char *) data;
        while (n && ssl && !shut) {
            const int r = SSL_write(ssl, q, (int) std::min<size_t>(n, 1 << 15));
            if (r <= 0) return false;
            q += r; n -= r;
        }
        return n == 0;
    }
    int  read(void *data, size_t n) { return ssl ? SSL_read(ssl, data, (int) n) : -1; }
    bool read_all(void *data, size_t n)
    {
        char *q = (char *) data;
        while (n && !shut) {
            const int r = read(q, n);
            if (r <= 0) return false;
            q += r; n -= r;
        }
        return n == 0;
    }
    void interrupt() { shut = true; if (fd >= 0) ::shutdown(fd, SHUT_RDWR); }
    SSL *handle() { return ssl; }
    void close()
    {
        if (ssl) { if (!shut) SSL_shutdown(ssl); SSL_free(ssl); ssl = nullptr; }
        if (ctx) { SSL_CTX_free(ctx); ctx = nullptr; }
        if (fd >= 0) { ::close(fd); fd = -1; }
    }

private:
    std::string tcp(const std::string &host, int port, int timeout_ms)
    {
        addrinfo hints{}, *res = nullptr;
        hints.ai_socktype = SOCK_STREAM;
        if (getaddrinfo(host.c_str(), std::to_string(port).c_str(), &hints, &res) != 0) return "cannot resolve the printer address";
        std::string err = "cannot reach the printer";
        for (addrinfo *a = res; a; a = a->ai_next) {
            fd = ::socket(a->ai_family, a->ai_socktype, a->ai_protocol);
            if (fd < 0) continue;
            int one = 1;
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
            const int fl = fcntl(fd, F_GETFL);
            fcntl(fd, F_SETFL, fl | O_NONBLOCK);
            int rc = ::connect(fd, a->ai_addr, a->ai_addrlen);
            if (rc != 0 && errno == EINPROGRESS) {
                pollfd p{fd, POLLOUT, 0};
                int e = 0; socklen_t len = sizeof(e);
                rc = (poll(&p, 1, timeout_ms) == 1 && getsockopt(fd, SOL_SOCKET, SO_ERROR, &e, &len) == 0 && e == 0) ? 0 : -1;
            }
            if (rc == 0) {
                fcntl(fd, F_SETFL, fl);
                struct timeval tv = {timeout_ms / 1000, 0};
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
                err.clear();
                break;
            }
            ::close(fd); fd = -1;
        }
        freeaddrinfo(res);
        return err;
    }
    int               fd = -1;
    SSL_CTX          *ctx = nullptr;
    SSL              *ssl = nullptr;
    std::mutex        mtx;
    std::atomic<bool> shut{false};
};

void put16(std::string &s, size_t v) { s += (char) (v >> 8); s += (char) (v & 0xff); }
void puts16(std::string &s, const std::string &t) { put16(s, t.size()); s += t; }
std::string packet(unsigned char type, const std::string &body)
{
    std::string s(1, (char) type);
    size_t n = body.size();
    do { unsigned char b = n % 128; n /= 128; if (n) b |= 128; s += (char) b; } while (n);
    return s + body;
}

// FTP control connection reply (last line of a possibly multi-line answer).
int ftp_reply(Tls &c, std::string &text)
{
    text.clear();
    std::string line; char ch;
    while (text.size() < 65536) {
        if (c.read(&ch, 1) != 1) return -1;
        if (ch != '\n') { if (ch != '\r') line += ch; continue; }
        text = line;
        if (line.size() >= 4 && isdigit(line[0]) && isdigit(line[1]) && isdigit(line[2]) && line[3] == ' ') return atoi(line.substr(0, 3).c_str());
        line.clear();
    }
    return -1;
}
int ftp_cmd(Tls &c, const std::string &cmd, std::string &text)
{
    const std::string s = cmd + "\r\n";
    return c.write(s.data(), s.size()) ? ftp_reply(c, text) : -1;
}
} // namespace

@implementation LanBridge {
    std::string           _host, _serial, _code, _ca;
    std::shared_ptr<Tls>  _mqtt, _cam;
    std::mutex            _m;
    std::atomic<int>      _seq;
}
- (instancetype)initWithHost:(NSString *)host serial:(NSString *)serial code:(NSString *)code ca:(NSString *)caFile
{
    if ((self = [super init])) { _host = host.UTF8String; _serial = serial.UTF8String; _code = code.UTF8String; _ca = caFile.UTF8String; _seq = 1; }
    return self;
}
- (nullable NSString *)connectMqtt:(void (^)(NSString *))onReport closed:(void (^)(NSString *))onClose
{
    auto t = std::make_shared<Tls>();
    std::string err = t->connect(_host, 8883, _serial, _ca);
    if (!err.empty()) return @(err.c_str());
    std::string body;
    puts16(body, "MQTT"); body += (char) 4; body += (char) 0xC2; put16(body, 60);
    puts16(body, "ipad-" + std::to_string(arc4random())); puts16(body, "bblp"); puts16(body, _code);
    const std::string con = packet(0x10, body);
    unsigned char ack[4];
    if (!t->write(con.data(), con.size()) || !t->read_all(ack, 4)) return @"the printer closed the connection";
    if (ack[0] != 0x20 || ack[3] != 0) return @"the access code was rejected";
    std::string sub;
    put16(sub, 1); puts16(sub, "device/" + _serial + "/report"); sub += (char) 0;
    const std::string sp = packet(0x82, sub);
    if (!t->write(sp.data(), sp.size())) return @"cannot subscribe";
    { std::lock_guard<std::mutex> l(_m); if (_mqtt) _mqtt->interrupt(); _mqtt = t; }
    std::thread([t, onReport, onClose] {
        while (true) @autoreleasepool {
            unsigned char type;
            if (!t->read_all(&type, 1)) break;
            size_t len = 0, mul = 1; unsigned char b = 0; int i = 0; bool ok = true;
            do { ok = t->read_all(&b, 1); len += (b & 127) * mul; mul *= 128; } while (ok && (b & 128) && ++i < 4);
            if (!ok || len > (8u << 20)) break;
            std::string pl(len, 0);
            if (len && !t->read_all(&pl[0], len)) break;
            if ((type & 0xF0) == 0x30 && len > 2) {
                const size_t tl = ((unsigned char) pl[0] << 8) | (unsigned char) pl[1];
                const size_t off = 2 + tl + ((type & 6) ? 2 : 0);
                if (off <= len) {
                    NSString *s = [[NSString alloc] initWithBytes:pl.data() + off length:len - off encoding:NSUTF8StringEncoding];
                    if (s) dispatch_async(dispatch_get_main_queue(), ^{ onReport(s); });
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ onClose(@"disconnected"); });
    }).detach();
    std::weak_ptr<Tls> w = t;
    std::thread([w] { // keep alive
        const std::string ping("\xC0\x00", 2);
        while (true) {
            std::this_thread::sleep_for(std::chrono::seconds(10));
            auto s = w.lock();
            if (!s || !s->write(ping.data(), 2)) break;
        }
    }).detach();
    return nil;
}
- (BOOL)publish:(NSString *)json
{
    std::shared_ptr<Tls> t;
    { std::lock_guard<std::mutex> l(_m); t = _mqtt; }
    if (!t) return NO;
    std::string body;
    puts16(body, "device/" + _serial + "/request");
    body += json.UTF8String;
    const std::string p = packet(0x30, body);
    return t->write(p.data(), p.size());
}
- (nullable NSString *)upload:(NSString *)file as:(NSString *)name progress:(void (^)(double))progress
{
    const std::string fname = name.UTF8String;
    if (fname.find_first_of("\r\n/") != std::string::npos) return @"invalid file name";
    FILE *f = fopen(file.UTF8String, "rb");
    if (!f) return @"cannot read the file";
    std::unique_ptr<FILE, int (*)(FILE *)> guard(f, fclose);
    fseek(f, 0, SEEK_END); const double total = std::max(1L, ftell(f)); fseek(f, 0, SEEK_SET);
    Tls c; std::string r;
    std::string err = c.connect(_host, 990, _serial, _ca);
    if (!err.empty()) return @(err.c_str());
    if (ftp_reply(c, r) != 220) return @"unexpected FTP greeting";
    if (ftp_cmd(c, "USER bblp", r) != 331) return @"FTP login refused";
    if (ftp_cmd(c, "PASS " + _code, r) != 230) return @"the access code was rejected";
    ftp_cmd(c, "PBSZ 0", r);
    if (ftp_cmd(c, "PROT P", r) != 200) return @"the printer refused a protected transfer";
    ftp_cmd(c, "TYPE I", r);
    if (ftp_cmd(c, "PASV", r) != 227) return @"passive mode refused";
    int h[6];
    const size_t q = r.find('(');
    if (q == std::string::npos || sscanf(r.c_str() + q, "(%d,%d,%d,%d,%d,%d)", h, h + 1, h + 2, h + 3, h + 4, h + 5) != 6) return @"bad passive reply";
    const std::string stor = "STOR " + fname + "\r\n";
    if (!c.write(stor.data(), stor.size())) return @"connection lost";
    SSL_SESSION *ses = SSL_get1_session(c.handle()); // the printer requires the data channel to resume the control session
    {
        Tls d;
        err = d.connect(_host, h[4] * 256 + h[5], _serial, _ca, ses);
        if (ses) SSL_SESSION_free(ses);
        if (!err.empty()) return @(("data channel: " + err).c_str());
        const int code = ftp_reply(c, r);
        if (code != 150 && code != 125) return @(("upload refused: " + r).c_str());
        std::vector<char> buf(1 << 16);
        double sent = 0; size_t n;
        while ((n = fread(buf.data(), 1, buf.size(), f)) > 0) {
            if (!d.write(buf.data(), n)) return @"the upload was interrupted";
            sent += n; progress(sent / total);
        }
    }
    const int code = ftp_reply(c, r);
    if (code != 226) return @(("upload not confirmed: " + r).c_str());
    ftp_cmd(c, "QUIT", r);
    return nil;
}
- (void)startCamera:(void (^)(NSData *))onFrame closed:(void (^)(NSString *))onClose
{
    auto t = std::make_shared<Tls>();
    { std::lock_guard<std::mutex> l(_m); if (_cam) _cam->interrupt(); _cam = t; }
    const std::string host = _host, serial = _serial, ca = _ca, code = _code;
    std::thread([=] {
        std::string err = t->connect(host, 6000, serial, ca);
        if (err.empty()) {
            unsigned char auth[80] = {0};
            const uint32_t head[4] = {0x40, 0x3000, 0, 0};
            memcpy(auth, head, 16);
            memcpy(auth + 16, "bblp", 4);
            memcpy(auth + 48, code.data(), std::min<size_t>(32, code.size()));
            if (!t->write(auth, sizeof(auth))) err = "camera refused";
        }
        while (err.empty()) @autoreleasepool {
            uint32_t h[4];
            if (!t->read_all(h, 16) || h[0] == 0 || h[0] > (8u << 20)) { err = "the camera stream ended"; break; }
            NSMutableData *d = [NSMutableData dataWithLength:h[0]];
            if (!t->read_all(d.mutableBytes, h[0])) { err = "the camera stream ended"; break; }
            dispatch_async(dispatch_get_main_queue(), ^{ onFrame(d); });
        }
        NSString *e = @(err.c_str());
        dispatch_async(dispatch_get_main_queue(), ^{ onClose(e); });
    }).detach();
}
- (void)stopCamera { std::lock_guard<std::mutex> l(_m); if (_cam) { _cam->interrupt(); _cam.reset(); } }
- (void)disconnect { [self stopCamera]; std::lock_guard<std::mutex> l(_m); if (_mqtt) { _mqtt->interrupt(); _mqtt.reset(); } }
- (void)dealloc { [self disconnect]; }
@end
