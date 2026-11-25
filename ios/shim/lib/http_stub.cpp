// No network on iPad yet: every request fails with an error callback. Only used by the log key download.
#include "slic3r/Utils/Http.hpp"
namespace Slic3r {
struct Http::priv { ErrorFn on_error; };
Http::Http(const std::string &) : p(new priv) {}
Http::Http(Http &&o) : p(std::move(o.p)) {}
Http::~Http() = default;
Http  Http::get(std::string url) { return Http(url); }
Http &Http::timeout_max(long) { return *this; }
Http &Http::on_complete(CompleteFn) { return *this; }
Http &Http::on_error(ErrorFn fn) { p->on_error = std::move(fn); return *this; }
void  Http::perform_sync() { if (p->on_error) p->on_error("", "network is not available", 0); }
}
