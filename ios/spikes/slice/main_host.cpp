#include "slice_core.hpp"
#include <cstdio>
int main(int argc, char **argv)
{
    if (argc != 4) { std::puts("usage: slice_host <resources> <models> <out>"); return 2; }
    return run_slice_cases(argv[1], argv[2], argv[3], [](const std::string &s) { std::puts(s.c_str()); std::fflush(stdout); });
}
